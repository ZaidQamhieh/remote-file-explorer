// Package pairing manages the one-time device pairing flow.
//
// On startup the agent calls New which generates a short random code,
// prints it prominently to the log, and renders a QR code to the terminal.
// The code is valid for a few minutes and can only be consumed once.
package pairing

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"sync"
	"time"

	"github.com/skip2/go-qrcode"
)

const (
	codeLen    = 8            // characters in the one-time code
	codeExpiry = 60 * time.Minute
	// Alphabet chosen to be easy to type: no 0/O, 1/I/l confusion.
	alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
)

// Manager generates and validates one-time pairing codes.
type Manager struct {
	mu      sync.Mutex
	code    string
	expires time.Time
}

// QRPayload is the JSON embedded in the QR code.
type QRPayload struct {
	Address          string `json:"address"`
	TailscaleAddress string `json:"tailscaleAddress,omitempty"`
	CertFingerprint  string `json:"certFingerprint"`
	PairingCode      string `json:"pairingCode"`
}

// New creates a Manager, generates the first code, and logs/prints the QR.
// lanAddress is the agent's LAN-reachable address (e.g. "192.168.1.5:8765");
// tailscaleAddress is its Tailscale-reachable address, or "" if unknown.
// fingerprint is the TLS cert's SHA-256 hex.
func New(lanAddress, tailscaleAddress, fingerprint string) (*Manager, error) {
	m := &Manager{}
	if err := m.rotate(lanAddress, tailscaleAddress, fingerprint); err != nil {
		return nil, err
	}
	return m, nil
}

// Consume validates code and clears it (single-use).
// Returns true on success.
func (m *Manager) Consume(code string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if code == "" || m.code == "" {
		return false
	}
	if code != m.code {
		return false
	}
	if time.Now().After(m.expires) {
		return false
	}
	m.code = "" // single-use
	return true
}

// rotate generates a new code and prints it.
func (m *Manager) rotate(lanAddress, tailscaleAddress, fingerprint string) error {
	code, err := randomCode(codeLen)
	if err != nil {
		return err
	}
	m.mu.Lock()
	m.code = code
	m.expires = time.Now().Add(codeExpiry)
	m.mu.Unlock()

	payload := QRPayload{
		Address:          lanAddress,
		TailscaleAddress: tailscaleAddress,
		CertFingerprint:  fingerprint,
		PairingCode:      code,
	}
	payloadJSON, _ := json.Marshal(payload)

	log.Printf("┌─────────────────────────────────────────┐")
	log.Printf("│  PAIRING CODE:  %-8s  (expires %s)  │", code, m.expires.Format("15:04:05"))
	log.Printf("└─────────────────────────────────────────┘")
	log.Printf("QR payload: %s", payloadJSON)

	// Render QR to terminal (medium recovery for robustness with display fonts).
	qr, err := qrcode.New(string(payloadJSON), qrcode.Medium)
	if err != nil {
		log.Printf("qr: %v", err)
		return nil // non-fatal
	}
	fmt.Println(qr.ToString(false))
	return nil
}

func randomCode(n int) (string, error) {
	b := make([]byte, n)
	for i := range b {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		b[i] = alphabet[idx.Int64()]
	}
	return string(b), nil
}
