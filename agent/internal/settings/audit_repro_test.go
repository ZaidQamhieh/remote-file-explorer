package settings

import (
	"os"
	"testing"
)

// Audit 2026-10-20 (F-93): a corrupt bandwidth limit is read as 0 (unlimited) without an error.
// Fails while the defect exists, so it runs only with RFE_AUDIT_REPRO=1.
func TestAuditRepro_CorruptThrottleIsNotSilentlyUnlimited(t *testing.T) {
	if os.Getenv("RFE_AUDIT_REPRO") != "1" {
		t.Skip("audit repro; set RFE_AUDIT_REPRO=1")
	}
	db := newDB(t)
	if err := db.SetConfig(keyMaxUploadBPS, "abc"); err != nil {
		t.Fatal(err)
	}
	if err := db.SetConfig(keyMaxDownloadBPS, "-5"); err != nil {
		t.Fatal(err)
	}
	s, err := Load(db, false, nil, "pc")
	if err == nil && (s.MaxUploadBytesPerSec() <= 0 || s.MaxDownloadBytesPerSec() <= 0) {
		t.Fatalf("corrupt limits loaded without error as upload=%d download=%d (<=0 means unlimited)",
			s.MaxUploadBytesPerSec(), s.MaxDownloadBytesPerSec())
	}
}
