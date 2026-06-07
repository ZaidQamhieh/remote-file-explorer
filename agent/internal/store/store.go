// Package store manages the agent's SQLite database.
// Tables: devices, config, transfers.
// Tokens are only stored as SHA-256 hashes.
package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	_ "modernc.org/sqlite" // pure-Go SQLite driver
)

// DB wraps the SQLite connection and exposes a typed API.
type DB struct {
	db *sql.DB
}

// Open opens (or creates) agent.db under dir.
func Open(dir string) (*DB, error) {
	path := dir + "/agent.db"
	// busy_timeout lets the daemon and the `rfe-agent` admin CLI write to the
	// same DB across processes without immediately erroring on a brief lock.
	db, err := sql.Open("sqlite", path+"?_journal_mode=WAL&_foreign_keys=on&_busy_timeout=5000")
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	db.SetMaxOpenConns(1) // SQLite WAL still prefers a single writer
	s := &DB{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// Close closes the database.
func (s *DB) Close() error { return s.db.Close() }

// migrate creates tables if they don't exist.
func (s *DB) migrate() error {
	_, err := s.db.Exec(`
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
`)
	if err != nil {
		return err
	}
	// Add the stable client identifier column to existing databases. A phone
	// sends a hardware-stable id (Android ID) when pairing so re-pairing the
	// same device reuses its row instead of piling up duplicates. Ignored when
	// the column already exists.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN client_id TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	return nil
}

// --------- devices ---------

// Device represents a paired device.
type Device struct {
	ID        string
	Label     string
	TokenHash string
	Created   time.Time
	LastSeen  time.Time
	Revoked   bool
}

// CreateDevice inserts a new device row. token is the raw bearer token —
// only its SHA-256 hash is stored.
func (s *DB) CreateDevice(id, label, token string) error {
	hash := hashToken(token)
	now := time.Now().Unix()
	_, err := s.db.Exec(
		`INSERT INTO devices (id,label,token_hash,created,last_seen,revoked) VALUES (?,?,?,?,?,0)`,
		id, label, hash, now, now,
	)
	return err
}

// UpsertDevice pairs a device, deduplicating by the hardware-stable clientID.
// If clientID is non-empty and a device with that clientID already exists, its
// token is rotated, it is un-revoked, and its existing id is returned — so a
// phone that re-pairs (after clearing app data, reinstalling, or losing its
// token) reuses its row instead of creating a duplicate. Otherwise a fresh
// device with a new UUID is inserted. Returns the device id to hand back to the
// client.
func (s *DB) UpsertDevice(clientID, label, token string) (string, error) {
	hash := hashToken(token)
	now := time.Now().Unix()

	if clientID != "" {
		var existingID string
		err := s.db.QueryRow(
			`SELECT id FROM devices WHERE client_id=?`, clientID,
		).Scan(&existingID)
		if err == nil {
			// Same phone re-pairing: rotate token, clear revoked, refresh label.
			if _, err := s.db.Exec(
				`UPDATE devices SET token_hash=?, label=?, last_seen=?, revoked=0 WHERE id=?`,
				hash, label, now, existingID,
			); err != nil {
				return "", err
			}
			return existingID, nil
		}
		if err != sql.ErrNoRows {
			return "", err
		}
	}

	id := uuid.New().String()
	if _, err := s.db.Exec(
		`INSERT INTO devices (id,label,token_hash,created,last_seen,revoked,client_id) VALUES (?,?,?,?,?,0,?)`,
		id, label, hash, now, now, clientID,
	); err != nil {
		return "", err
	}
	return id, nil
}

// DeviceByToken returns the device whose token matches the given raw token,
// or (nil,nil) if not found.
func (s *DB) DeviceByToken(token string) (*Device, error) {
	hash := hashToken(token)
	row := s.db.QueryRow(
		`SELECT id,label,token_hash,created,last_seen,revoked FROM devices WHERE token_hash=?`, hash,
	)
	d, err := scanDevice(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return d, err
}

// TouchDevice updates last_seen for the given id.
func (s *DB) TouchDevice(id string) error {
	_, err := s.db.Exec(`UPDATE devices SET last_seen=? WHERE id=?`, time.Now().Unix(), id)
	return err
}

func scanDevice(row *sql.Row) (*Device, error) {
	var d Device
	var created, lastSeen int64
	var revoked int
	err := row.Scan(&d.ID, &d.Label, &d.TokenHash, &created, &lastSeen, &revoked)
	if err != nil {
		return nil, err
	}
	d.Created = time.Unix(created, 0)
	d.LastSeen = time.Unix(lastSeen, 0)
	d.Revoked = revoked != 0
	return &d, nil
}

// rowScanner is satisfied by both *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanDeviceFrom(sc rowScanner) (*Device, error) {
	var d Device
	var created, lastSeen int64
	var revoked int
	if err := sc.Scan(&d.ID, &d.Label, &d.TokenHash, &created, &lastSeen, &revoked); err != nil {
		return nil, err
	}
	d.Created = time.Unix(created, 0)
	d.LastSeen = time.Unix(lastSeen, 0)
	d.Revoked = revoked != 0
	return &d, nil
}

// ListDevices returns all paired devices (including revoked), oldest first.
func (s *DB) ListDevices() ([]Device, error) {
	rows, err := s.db.Query(
		`SELECT id,label,token_hash,created,last_seen,revoked FROM devices ORDER BY created`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Device
	for rows.Next() {
		d, err := scanDeviceFrom(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

// ResolveDeviceID maps a full id or a unique id prefix to a full device id, for
// convenient CLI use (e.g. "revoke 9789"). Returns an error if the prefix
// matches no device or more than one.
func (s *DB) ResolveDeviceID(prefix string) (string, error) {
	if prefix == "" {
		return "", fmt.Errorf("empty device id")
	}
	devices, err := s.ListDevices()
	if err != nil {
		return "", err
	}
	var matches []string
	for _, d := range devices {
		if d.ID == prefix {
			return d.ID, nil // exact match wins immediately
		}
		if strings.HasPrefix(d.ID, prefix) {
			matches = append(matches, d.ID)
		}
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("no device matches %q", prefix)
	case 1:
		return matches[0], nil
	default:
		return "", fmt.Errorf("%q is ambiguous (%d devices match)", prefix, len(matches))
	}
}

// RevokeDevice marks a device revoked; its token is rejected by authMiddleware.
func (s *DB) RevokeDevice(id string) error {
	_, err := s.db.Exec(`UPDATE devices SET revoked=1 WHERE id=?`, id)
	return err
}

// DeleteDevice permanently removes a device row. Used to clear out revoked
// devices so the paired-devices list doesn't accumulate stale entries.
func (s *DB) DeleteDevice(id string) error {
	_, err := s.db.Exec(`DELETE FROM devices WHERE id=?`, id)
	return err
}

// --------- pairing codes ---------

// CreatePairingCode stores a one-time pairing code valid until expires. Stored
// in the DB (not daemon memory) so the `rfe-agent pair` CLI can mint a code the
// running daemon will accept, without a restart. Opportunistically clears
// already-expired codes.
func (s *DB) CreatePairingCode(code string, expires time.Time) error {
	_, _ = s.db.Exec(`DELETE FROM pairing_codes WHERE expires < ?`, time.Now().Unix())
	_, err := s.db.Exec(
		`INSERT OR REPLACE INTO pairing_codes (code, expires) VALUES (?, ?)`,
		code, expires.Unix(),
	)
	return err
}

// ConsumePairingCode validates code and removes it (single-use). Returns true
// only if the code exists and has not expired.
func (s *DB) ConsumePairingCode(code string) bool {
	if code == "" {
		return false
	}
	var expires int64
	err := s.db.QueryRow(
		`SELECT expires FROM pairing_codes WHERE code=?`, code,
	).Scan(&expires)
	if err != nil {
		return false
	}
	// Remove it regardless (single-use); only accept if still valid.
	_, _ = s.db.Exec(`DELETE FROM pairing_codes WHERE code=?`, code)
	return time.Now().Unix() <= expires
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// --------- config ---------

// GetConfig retrieves a config value by key.
func (s *DB) GetConfig(key string) (string, error) {
	var val string
	err := s.db.QueryRow(`SELECT value FROM config WHERE key=?`, key).Scan(&val)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return val, err
}

// SetConfig upserts a config value.
func (s *DB) SetConfig(key, value string) error {
	_, err := s.db.Exec(
		`INSERT INTO config(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`,
		key, value,
	)
	return err
}

// --------- transfers ---------

// Transfer is an in-progress or completed upload session.
type Transfer struct {
	ID             string
	TargetPath     string
	TotalSize      int64
	ChunkSize      int
	SHA256         string
	ReceivedChunks []int
	Status         string // open | completed | failed
	TempPath       string
	TotalChunks    int
}

// CreateTransfer inserts a new transfer row.
func (s *DB) CreateTransfer(t *Transfer) error {
	chunks, _ := json.Marshal([]int{})
	_, err := s.db.Exec(
		`INSERT INTO transfers (id,target_path,total_size,chunk_size,sha256,received_chunks,status,temp_path,total_chunks)
         VALUES (?,?,?,?,?,?,?,?,?)`,
		t.ID, t.TargetPath, t.TotalSize, t.ChunkSize, t.SHA256,
		string(chunks), "open", t.TempPath, t.TotalChunks,
	)
	return err
}

// GetTransfer retrieves a transfer by ID.
func (s *DB) GetTransfer(id string) (*Transfer, error) {
	row := s.db.QueryRow(
		`SELECT id,target_path,total_size,chunk_size,sha256,received_chunks,status,temp_path,total_chunks
         FROM transfers WHERE id=?`, id,
	)
	return scanTransfer(row)
}

// MarkChunkReceived atomically records chunk n as received.
func (s *DB) MarkChunkReceived(id string, n int) error {
	t, err := s.GetTransfer(id)
	if err != nil {
		return err
	}
	// Add n if not already present.
	set := make(map[int]struct{}, len(t.ReceivedChunks)+1)
	for _, c := range t.ReceivedChunks {
		set[c] = struct{}{}
	}
	set[n] = struct{}{}
	updated := make([]int, 0, len(set))
	for c := range set {
		updated = append(updated, c)
	}
	// Sort for determinism.
	sortInts(updated)
	b, _ := json.Marshal(updated)
	_, err = s.db.Exec(`UPDATE transfers SET received_chunks=? WHERE id=?`, string(b), id)
	return err
}

// SetTransferStatus updates the status of a transfer.
func (s *DB) SetTransferStatus(id, status string) error {
	_, err := s.db.Exec(`UPDATE transfers SET status=? WHERE id=?`, status, id)
	return err
}

func scanTransfer(row *sql.Row) (*Transfer, error) {
	var t Transfer
	var chunksJSON string
	err := row.Scan(
		&t.ID, &t.TargetPath, &t.TotalSize, &t.ChunkSize, &t.SHA256,
		&chunksJSON, &t.Status, &t.TempPath, &t.TotalChunks,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal([]byte(chunksJSON), &t.ReceivedChunks)
	return &t, nil
}

func sortInts(a []int) {
	// Simple insertion sort — chunk lists are tiny.
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}
