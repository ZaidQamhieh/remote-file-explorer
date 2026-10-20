package main

import (
	"testing"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// Audit F-118: device changes made from the CLI must reach the audit trail.
func TestCliAuditWritesAnEntry(t *testing.T) {
	db, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	cliAudit(db, store.AuditDeviceRevoked, "dev-1", "")
	entries, err := db.AuditEntries(10, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Action != store.AuditDeviceRevoked || entries[0].Actor != cliActor || entries[0].Target != "dev-1" {
		t.Fatalf("audit entries = %+v", entries)
	}
}
