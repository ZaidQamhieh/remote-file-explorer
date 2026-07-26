package server

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestWriteInternalErrorDoesNotExposeDetails(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/v1/status", nil)
	w := httptest.NewRecorder()
	writeInternalError(w, r, errors.New("open /home/alice/private.txt: permission denied"))

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusInternalServerError)
	}
	var got apiError
	if err := json.NewDecoder(w.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if got.Code != "INTERNAL" || got.Message != "internal server error" {
		t.Fatalf("response = %#v", got)
	}
	if strings.Contains(w.Body.String(), "/home/alice") {
		t.Fatalf("response leaked filesystem details: %s", w.Body.String())
	}
}
