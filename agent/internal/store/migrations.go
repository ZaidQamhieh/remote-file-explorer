package store

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
)

// migrations are applied in order, each in its own transaction, after which
// PRAGMA user_version is bumped to its 1-based index. A step therefore either
// lands completely or not at all — the previous chain ran bare ALTERs one by
// one, so a failure halfway left a schema no version number described (PR-46).
//
// Every step must stay IDEMPOTENT. Databases predating user_version report 0
// and so replay the whole list, and the baseline step is exactly the old chain:
// CREATE TABLE IF NOT EXISTS, addColumn's duplicate tolerance, and
// CREATE INDEX IF NOT EXISTS. Append new steps; never renumber or edit a
// shipped one.
var migrations = []func(*sql.Tx) error{
	migrateBaseline,
	migrateChunkTable,
}

// migrate brings the schema up to len(migrations).
func (s *DB) migrate() error {
	var version int
	if err := s.db.QueryRow(`PRAGMA user_version`).Scan(&version); err != nil {
		return fmt.Errorf("read schema version: %w", err)
	}
	if version > len(migrations) {
		// The DB was written by a newer agent. Refuse rather than run old code
		// against a schema it doesn't know.
		return fmt.Errorf("database schema version %d is newer than this agent supports (%d)", version, len(migrations))
	}
	for i := version; i < len(migrations); i++ {
		tx, err := s.db.Begin()
		if err != nil {
			return fmt.Errorf("migration %d: begin: %w", i+1, err)
		}
		if err := migrations[i](tx); err != nil {
			tx.Rollback() //nolint:errcheck // the migration error is what matters
			return fmt.Errorf("migration %d: %w", i+1, err)
		}
		// PRAGMA takes no bind parameters, hence the format string; i is a
		// loop index over a package-level slice, not user input.
		if _, err := tx.Exec(fmt.Sprintf(`PRAGMA user_version = %d`, i+1)); err != nil {
			tx.Rollback() //nolint:errcheck
			return fmt.Errorf("migration %d: set version: %w", i+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("migration %d: commit: %w", i+1, err)
		}
	}
	return nil
}

// addColumn adds a column, tolerating the case where it already exists.
// SQLite has no ADD COLUMN IF NOT EXISTS, so the duplicate has to be
// recognised from the error text — centralised here rather than repeated at
// every call site.
func addColumn(tx *sql.Tx, table, column, spec string) error {
	_, err := tx.Exec(fmt.Sprintf(`ALTER TABLE %s ADD COLUMN %s %s`, table, column, spec))
	if err != nil && strings.Contains(err.Error(), "duplicate column name") {
		return nil
	}
	return err
}

// migrateBaseline is the schema as it stood when versioning was introduced:
// the original CREATE TABLEs plus every column/index added by PR-03, PR-41,
// PR-43, PR-44 and PR-50 before this file tracked versions.
func migrateBaseline(tx *sql.Tx) error {
	_, err := tx.Exec(`
CREATE TABLE IF NOT EXISTS devices (
    id          TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    token_hash  TEXT NOT NULL UNIQUE,
    created     INTEGER NOT NULL,
    last_seen   INTEGER NOT NULL,
    revoked     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pairing_codes (
    code    TEXT PRIMARY KEY,
    expires INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS transfers (
    id               TEXT PRIMARY KEY,
    target_path      TEXT NOT NULL,
    total_size       INTEGER NOT NULL,
    chunk_size       INTEGER NOT NULL,
    sha256           TEXT NOT NULL,
    received_chunks  TEXT NOT NULL DEFAULT '[]',
    status           TEXT NOT NULL DEFAULT 'open',
    temp_path        TEXT NOT NULL,
    total_chunks     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS share_tokens (
    token_hash  TEXT PRIMARY KEY,
    path        TEXT NOT NULL,
    created     INTEGER NOT NULL,
    expires     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS share_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    token_hash   TEXT NOT NULL,
    path         TEXT NOT NULL,
    minted_at    INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    served_at    INTEGER,
    requester_ip TEXT
);

CREATE TABLE IF NOT EXISTS users (
    username      TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    created       INTEGER NOT NULL
);
`)
	if err != nil {
		return err
	}
	// Add the stable client identifier column to existing databases. A phone
	// sends a hardware-stable id (Android ID) when pairing so re-pairing the
	// same device reuses its row instead of piling up duplicates. Ignored when
	// the column already exists.
	if err := addColumn(tx, "devices", "client_id", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add columns recording the client's last-seen network address and
	// last-reported app version, refreshed on every authenticated request.
	// Ignored when the columns already exist.
	if err := addColumn(tx, "devices", "last_address", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	if err := addColumn(tx, "devices", "last_version", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add the per-device path-jail column (H2). Empty means "no per-device
	// restriction" — the device gets the agent's full configured root jail,
	// preserving today's behavior for existing rows.
	if err := addColumn(tx, "devices", "jail_root", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add the per-device read-only column (#8). 0 means no restriction;
	// existing rows default to read-write, preserving today's behavior. When
	// set, the device may browse/download but every filesystem write is
	// rejected with READ_ONLY.
	if err := addColumn(tx, "devices", "read_only", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	// Add the pinned device public key (base64 Ed25519, TOFU-pinned at
	// pair/login time — see security.VerifyDeviceSignature). Empty means
	// "not yet pinned", true for every row created before this feature and
	// for the brief window between UpsertDevice inserting a row and the
	// caller pinning its first key.
	if err := addColumn(tx, "devices", "public_key", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add the via_login column: set when a device's current token was
	// obtained via /login or /register (proof of the single account's
	// password) rather than /pair (a one-time code meant for ordinary
	// devices like the phone app). Devices with via_login=1 are treated as
	// the owner and may administer OTHER devices (mint pairing codes,
	// revoke/jail/read-only-toggle); existing rows default to 0, preserving
	// today's self-only behavior.
	if err := addColumn(tx, "devices", "via_login", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	// Add the username column: which login account authenticated this device,
	// stamped by /login and /register (empty for /pair devices and rows
	// created before this column — they get stamped on their next login).
	// Feeds the Transfers page's user filter via the device_id join.
	if err := addColumn(tx, "devices", "username", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add guest-mode defaults to pairing_codes: an admin minting a "guest"
	// pairing code sets these so the resulting device is created already
	// read-only and jailed, instead of needing a second admin PATCH after
	// pairing. Empty/0 means "no guest defaults" (today's behavior).
	if err := addColumn(tx, "pairing_codes", "jail_root", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	if err := addColumn(tx, "pairing_codes", "read_only", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	// Add the owning device to transfers, so the web companion's Transfers
	// page can filter by device. Empty means "no device recorded" (rows
	// created before this feature). Populated from the auth-context device
	// at session-open time — see OpenSession's caller.
	if err := addColumn(tx, "transfers", "device_id", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// Add a last-write timestamp to transfers, stamped on every received
	// chunk. Lets the web companion distinguish "genuinely in-flight right
	// now" from the thousands of stale never-finalized "open" rows that
	// accumulate over time (see CountActiveTransfers). 0 means never written
	// since this column was added.
	if err := addColumn(tx, "transfers", "updated_at", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	// PR-50: persist the session's overwrite flag. Complete re-checks it at
	// publish time (OpenSession's check races anything created during the
	// upload). Rows predating this column default to 0 = no-replace, the safe
	// side: a completing legacy session now conflicts instead of clobbering.
	if err := addColumn(tx, "transfers", "overwrite", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	// PR-03: record which device minted each share token, so the share list
	// and revoke are scoped to their owner instead of being global. Empty
	// means "no device recorded" (tokens minted before this column) — those
	// are admin-only, same rule legacy transfer rows get.
	if err := addColumn(tx, "share_tokens", "device_id", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}
	// PR-44: enforce one logical device per hardware-stable client_id. Collapse
	// any pre-existing duplicates (keeping the most recently inserted row) before
	// adding the partial unique index, so upgrades of a DB that already piled up
	// duplicates don't fail. Empty client_id (login/register devices) is exempt.
	if _, err := tx.Exec(`
DELETE FROM devices WHERE client_id != '' AND rowid NOT IN (
    SELECT MAX(rowid) FROM devices WHERE client_id != '' GROUP BY client_id
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_client_id ON devices(client_id) WHERE client_id != '';
`); err != nil {
		return err
	}
	// PR-43: index the transfer-listing/cleanup access patterns (admin pages
	// filter by status/recency and by device). No retention job yet — that is a
	// separate background sweeper.
	if _, err := tx.Exec(`
CREATE INDEX IF NOT EXISTS idx_transfers_status_updated ON transfers(status, updated_at);
CREATE INDEX IF NOT EXISTS idx_transfers_device_updated ON transfers(device_id, updated_at);
`); err != nil {
		return err
	}
	return nil
}

// migrateChunkTable normalizes received-chunk tracking (PR-42). The old
// design kept a JSON array in transfers.received_chunks and rewrote the whole
// array on every chunk: quadratic over a transfer, and a read-modify-write
// that only a transaction kept from losing updates. A row per chunk makes
// recording one chunk an O(1) indexed insert that cannot collide.
//
// The JSON column is backfilled and then dropped, so there is no second copy
// left to drift out of sync with the table.
func migrateChunkTable(tx *sql.Tx) error {
	if _, err := tx.Exec(`
CREATE TABLE IF NOT EXISTS transfer_chunks (
    transfer_id TEXT NOT NULL,
    chunk_no    INTEGER NOT NULL,
    PRIMARY KEY (transfer_id, chunk_no)
) WITHOUT ROWID;
`); err != nil {
		return err
	}

	// Backfill only if the legacy column is still present — this step is
	// replayed against databases that already dropped it (user_version=0
	// upgrade path), and re-running must be a no-op.
	var legacy int
	if err := tx.QueryRow(
		`SELECT COUNT(*) FROM pragma_table_info('transfers') WHERE name='received_chunks'`,
	).Scan(&legacy); err != nil {
		return err
	}
	if legacy == 0 {
		return nil
	}

	rows, err := tx.Query(`SELECT id, received_chunks FROM transfers`)
	if err != nil {
		return err
	}
	backfill := map[string][]int{}
	for rows.Next() {
		var id, chunksJSON string
		if err := rows.Scan(&id, &chunksJSON); err != nil {
			rows.Close()
			return err
		}
		var received []int
		// A row whose JSON is unreadable loses its resume progress, not its
		// data: the client re-uploads the chunks it can no longer prove it sent.
		_ = json.Unmarshal([]byte(chunksJSON), &received)
		if len(received) > 0 {
			backfill[id] = received
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()

	for id, received := range backfill {
		for _, n := range received {
			if _, err := tx.Exec(
				`INSERT OR IGNORE INTO transfer_chunks (transfer_id, chunk_no) VALUES (?,?)`, id, n,
			); err != nil {
				return err
			}
		}
	}

	_, err = tx.Exec(`ALTER TABLE transfers DROP COLUMN received_chunks`)
	return err
}
