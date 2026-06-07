package store

import (
	"testing"
	"time"
)

func TestListAndRevokeDevices(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create a: %v", err)
	}
	if err := db.CreateDevice("id-2", "phone-b", "tok-b"); err != nil {
		t.Fatalf("create b: %v", err)
	}

	list, err := db.ListDevices()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 devices, got %d", len(list))
	}

	if err := db.RevokeDevice("id-1"); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	// A revoked device's token no longer resolves to a usable device.
	d, err := db.DeviceByToken("tok-a")
	if err != nil {
		t.Fatalf("by token: %v", err)
	}
	if d == nil || !d.Revoked {
		t.Fatalf("expected device present and revoked, got %+v", d)
	}
}

func TestUpsertDeviceDedupesByClientID(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	// First pairing of a phone with a stable client id.
	id1, err := db.UpsertDevice("android-abc", "Mobile App", "tok-1")
	if err != nil {
		t.Fatalf("upsert 1: %v", err)
	}
	// Simulate a revoke, then a re-pair of the SAME phone (e.g. after the user
	// cleared app data). It must reuse the same row, not create a second one.
	if err := db.RevokeDevice(id1); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	id2, err := db.UpsertDevice("android-abc", "Mobile App", "tok-2")
	if err != nil {
		t.Fatalf("upsert 2: %v", err)
	}
	if id2 != id1 {
		t.Fatalf("re-pair should reuse device id %q, got %q", id1, id2)
	}

	list, err := db.ListDevices()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 device after re-pair, got %d", len(list))
	}
	if list[0].Revoked {
		t.Fatalf("re-pair should clear the revoked flag")
	}
	// The new token works; the old one no longer resolves to this device.
	if d, _ := db.DeviceByToken("tok-2"); d == nil || d.ID != id1 {
		t.Fatalf("new token should resolve to the reused device")
	}

	// A different phone (distinct client id) still gets its own row.
	if _, err := db.UpsertDevice("android-xyz", "Mobile App", "tok-3"); err != nil {
		t.Fatalf("upsert other: %v", err)
	}
	if list, _ := db.ListDevices(); len(list) != 2 {
		t.Fatalf("a distinct phone should add a row, got %d", len(list))
	}

	// Empty client id (legacy/non-Android) never dedups — each call is new.
	a, _ := db.UpsertDevice("", "Legacy", "tok-4")
	b, _ := db.UpsertDevice("", "Legacy", "tok-5")
	if a == b {
		t.Fatalf("empty client id must not dedup")
	}
}

func TestPairingCodeLifecycle(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	// A valid code can be consumed exactly once.
	if err := db.CreatePairingCode("ABC123", time.Now().Add(time.Hour)); err != nil {
		t.Fatalf("create: %v", err)
	}
	if !db.ConsumePairingCode("ABC123") {
		t.Fatalf("expected first consume to succeed")
	}
	if db.ConsumePairingCode("ABC123") {
		t.Fatalf("expected second consume to fail (single-use)")
	}

	// An expired code is rejected.
	if err := db.CreatePairingCode("OLD999", time.Now().Add(-time.Minute)); err != nil {
		t.Fatalf("create expired: %v", err)
	}
	if db.ConsumePairingCode("OLD999") {
		t.Fatalf("expected expired code to be rejected")
	}

	// An unknown code is rejected.
	if db.ConsumePairingCode("NOPE") {
		t.Fatalf("expected unknown code to be rejected")
	}
}

func TestResolveDeviceIDByPrefix(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	if err := db.CreateDevice("9789abcd-1111", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create a: %v", err)
	}
	if err := db.CreateDevice("9789ffff-2222", "phone-b", "tok-b"); err != nil {
		t.Fatalf("create b: %v", err)
	}
	if err := db.CreateDevice("0000eeee-3333", "phone-c", "tok-c"); err != nil {
		t.Fatalf("create c: %v", err)
	}

	// Unique prefix resolves.
	if got, err := db.ResolveDeviceID("0000"); err != nil || got != "0000eeee-3333" {
		t.Fatalf("unique prefix: got %q err %v", got, err)
	}
	// Exact id resolves even when it's also a prefix of itself.
	if got, err := db.ResolveDeviceID("9789abcd-1111"); err != nil || got != "9789abcd-1111" {
		t.Fatalf("exact id: got %q err %v", got, err)
	}
	// Ambiguous prefix errors.
	if _, err := db.ResolveDeviceID("9789"); err == nil {
		t.Fatalf("expected ambiguous prefix to error")
	}
	// No match errors.
	if _, err := db.ResolveDeviceID("zzzz"); err == nil {
		t.Fatalf("expected no-match to error")
	}
}

func TestDeleteDeviceRemovesRow(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	if err := db.CreateDevice("id-1", "phone-a", "tok-a"); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := db.DeleteDevice("id-1"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	list, err := db.ListDevices()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 0 {
		t.Fatalf("expected device removed, got %d rows", len(list))
	}
}
