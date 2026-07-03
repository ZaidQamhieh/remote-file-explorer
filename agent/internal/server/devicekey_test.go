package server

import (
	"crypto/ed25519"
	"encoding/base64"
	"testing"
)

// signedDeviceProof mints a fresh nonce from nonces and signs it with a new
// Ed25519 keypair, returning the (publicKey, nonce, signature) triple that
// pair/login/register expect for device-identity proof-of-possession.
func signedDeviceProof(t *testing.T, nonces *nonceStore) (publicKey, nonce, signature string) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	nonce, err = nonces.Mint()
	if err != nil {
		t.Fatalf("mint nonce: %v", err)
	}
	sig := ed25519.Sign(priv, []byte(nonce))
	return base64.StdEncoding.EncodeToString(pub), nonce, base64.StdEncoding.EncodeToString(sig)
}
