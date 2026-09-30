package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/pairing"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

const (
	testFp    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	testCNonc = "00112233445566778899aabbccddeeff"
)

type pairReqEnv struct {
	t      *testing.T
	db     *store.DB
	cfg    Config
	nonces *nonceStore
	prompt *PairPrompt
	create http.HandlerFunc
	poll   http.HandlerFunc
}

func newPairReqEnv(t *testing.T) *pairReqEnv {
	db, _ := newTestDeps(t)
	e := &pairReqEnv{t: t, db: db, nonces: newNonceStore()}
	e.cfg = Config{Name: "test-pc", CertFingerprint: testFp, OnPairRequest: func(p PairPrompt) { e.prompt = &p }}
	e.create = createPairRequestHandler(e.cfg, db, e.nonces)
	e.poll = pollPairRequestHandler(e.cfg, db)
	return e
}

func (e *pairReqEnv) request(clientNonce string) *httptest.ResponseRecorder {
	pub, nonce, sig := signedDeviceProof(e.t, e.nonces)
	body := `{"deviceLabel":"Pixel","devicePublicKey":"` + pub + `","nonce":"` + nonce + `","signature":"` + sig + `","clientNonce":"` + clientNonce + `"}`
	rr := httptest.NewRecorder()
	e.create(rr, httptest.NewRequest(http.MethodPost, "/v1/pair/request", strings.NewReader(body)))
	return rr
}

func (e *pairReqEnv) pollStatus(id, nonce string) (int, map[string]any) {
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/pair/request/"+id+"?nonce="+nonce, nil)
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", id)
	req = req.WithContext(withChiCtx(req, rctx))
	e.poll(rr, req)
	var out map[string]any
	_ = json.Unmarshal(rr.Body.Bytes(), &out)
	return rr.Code, out
}

func TestPairRequest_ApprovedFlowMintsTokenOnce(t *testing.T) {
	e := newPairReqEnv(t)
	rr := e.request(testCNonc)
	if rr.Code != http.StatusOK {
		t.Fatalf("create: %d %s", rr.Code, rr.Body.String())
	}
	var created struct{ RequestID string }
	_ = json.Unmarshal(rr.Body.Bytes(), &created)
	if created.RequestID == "" || e.prompt == nil {
		t.Fatalf("missing id or prompt: %+v %+v", created, e.prompt)
	}
	want, _ := pairing.SAS(testFp, testCNonc, created.RequestID)
	if e.prompt.SAS != want || e.prompt.Label != "Pixel" {
		t.Fatalf("prompt %+v, want SAS %s", e.prompt, want)
	}
	if strings.Contains(rr.Body.String(), want) || strings.Contains(rr.Body.String(), testFp) {
		t.Fatal("create response must not carry the match code or the fingerprint")
	}

	if code, out := e.pollStatus(created.RequestID, testCNonc); code != 200 || out["status"] != "pending" {
		t.Fatalf("pending poll: %d %v", code, out)
	}
	if err := e.db.DecidePairRequest(created.RequestID, true); err != nil {
		t.Fatal(err)
	}
	code, out := e.pollStatus(created.RequestID, testCNonc)
	if code != 200 || out["status"] != "approved" || out["deviceToken"] == "" || out["deviceId"] == "" {
		t.Fatalf("approved poll: %d %v", code, out)
	}
	if code, _ := e.pollStatus(created.RequestID, testCNonc); code != http.StatusNotFound {
		t.Fatalf("token must be collectable once, second poll got %d", code)
	}
}

func TestPairRequest_RejectedAndWrongNonce(t *testing.T) {
	e := newPairReqEnv(t)
	var created struct{ RequestID string }
	_ = json.Unmarshal(e.request(testCNonc).Body.Bytes(), &created)
	if code, _ := e.pollStatus(created.RequestID, strings.Repeat("ff", 16)); code != http.StatusNotFound {
		t.Fatalf("wrong nonce got %d", code)
	}
	if err := e.db.DecidePairRequest(created.RequestID, false); err != nil {
		t.Fatal(err)
	}
	if _, out := e.pollStatus(created.RequestID, testCNonc); out["status"] != "rejected" {
		t.Fatalf("got %v", out)
	}
	if e.db.DecidePairRequest(created.RequestID, true) == nil {
		t.Fatal("a decided request must not be re-decided")
	}
	if devs, _ := e.db.ListDevices(); len(devs) != 0 {
		t.Fatalf("rejection must not create a device: %v", devs)
	}
}

func TestPairRequest_ValidatesAndBoundsPending(t *testing.T) {
	e := newPairReqEnv(t)
	if rr := e.request("nothex"); rr.Code != http.StatusBadRequest {
		t.Fatalf("bad clientNonce: %d", rr.Code)
	}
	rr := httptest.NewRecorder()
	e.create(rr, httptest.NewRequest(http.MethodPost, "/v1/pair/request", strings.NewReader(`{"clientNonce":"`+testCNonc+`"}`)))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("missing proof: %d", rr.Code)
	}
	for i := 0; i < store.MaxPendingPairRequests; i++ {
		if rr := e.request(testCNonc); rr.Code != http.StatusOK {
			t.Fatalf("request %d: %d %s", i, rr.Code, rr.Body.String())
		}
	}
	if rr := e.request(testCNonc); rr.Code != http.StatusTooManyRequests {
		t.Fatalf("over the pending cap: %d", rr.Code)
	}
}

func TestSanitizeLabel(t *testing.T) {
	if got := sanitizeLabel("a\nb\x00c"); got != "abc" {
		t.Fatalf("got %q", got)
	}
	if got := sanitizeLabel(strings.Repeat("x", 100)); len(got) != 40 {
		t.Fatalf("len %d", len(got))
	}
	if sanitizeLabel("\n") != "unnamed-device" {
		t.Fatal("empty label fallback")
	}
}

func withChiCtx(r *http.Request, rctx *chi.Context) context.Context {
	return context.WithValue(r.Context(), chi.RouteCtxKey, rctx)
}
