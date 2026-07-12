// Package store manages the agent's SQLite database.
// Tables: devices, config, transfers.
// Tokens are only stored as SHA-256 hashes.
package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
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
	path := filepath.Join(dir, "agent.db")
	// busy_timeout lets the daemon and the `rfe-agent` admin CLI write to the
	// same DB across processes without immediately erroring on a brief lock.
	// modernc.org/sqlite only recognizes `_pragma` (plus `_time_format` and
	// `_txlock`) DSN params, not the mattn-style `_journal_mode`/`_busy_timeout`
	// keys — those would be silently ignored.
	dsn := path + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(on)"
	db, err := sql.Open("sqlite", dsn)
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
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN client_id TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add columns recording the client's last-seen network address and
	// last-reported app version, refreshed on every authenticated request.
	// Ignored when the columns already exist.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN last_address TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN last_version TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add the per-device path-jail column (H2). Empty means "no per-device
	// restriction" — the device gets the agent's full configured root jail,
	// preserving today's behavior for existing rows.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN jail_root TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add the per-device read-only column (#8). 0 means no restriction;
	// existing rows default to read-write, preserving today's behavior. When
	// set, the device may browse/download but every filesystem write is
	// rejected with READ_ONLY.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN read_only INTEGER NOT NULL DEFAULT 0`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add the pinned device public key (base64 Ed25519, TOFU-pinned at
	// pair/login time — see security.VerifyDeviceSignature). Empty means
	// "not yet pinned", true for every row created before this feature and
	// for the brief window between UpsertDevice inserting a row and the
	// caller pinning its first key.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN public_key TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add the via_login column: set when a device's current token was
	// obtained via /login or /register (proof of the single account's
	// password) rather than /pair (a one-time code meant for ordinary
	// devices like the phone app). Devices with via_login=1 are treated as
	// the owner and may administer OTHER devices (mint pairing codes,
	// revoke/jail/read-only-toggle); existing rows default to 0, preserving
	// today's self-only behavior.
	if _, err := s.db.Exec(
		`ALTER TABLE devices ADD COLUMN via_login INTEGER NOT NULL DEFAULT 0`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add guest-mode defaults to pairing_codes: an admin minting a "guest"
	// pairing code sets these so the resulting device is created already
	// read-only and jailed, instead of needing a second admin PATCH after
	// pairing. Empty/0 means "no guest defaults" (today's behavior).
	if _, err := s.db.Exec(
		`ALTER TABLE pairing_codes ADD COLUMN jail_root TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	if _, err := s.db.Exec(
		`ALTER TABLE pairing_codes ADD COLUMN read_only INTEGER NOT NULL DEFAULT 0`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add the owning device to transfers, so the web companion's Transfers
	// page can filter by device. Empty means "no device recorded" (rows
	// created before this feature). Populated from the auth-context device
	// at session-open time — see OpenSession's caller.
	if _, err := s.db.Exec(
		`ALTER TABLE transfers ADD COLUMN device_id TEXT NOT NULL DEFAULT ''`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	// Add a last-write timestamp to transfers, stamped on every received
	// chunk. Lets the web companion distinguish "genuinely in-flight right
	// now" from the thousands of stale never-finalized "open" rows that
	// accumulate over time (see CountActiveTransfers). 0 means never written
	// since this column was added.
	if _, err := s.db.Exec(
		`ALTER TABLE transfers ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0`,
	); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		return err
	}
	return nil
}

// --------- devices ---------

// Device represents a paired device.
type Device struct {
	ID          string
	Label       string
	TokenHash   string
	Created     time.Time
	LastSeen    time.Time
	Revoked     bool
	LastAddress string
	LastVersion string
	JailRoot    string
	ReadOnly    bool
	PublicKey   string
	ViaLogin    bool
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

// DevicePublicKeyByClientID returns the pinned public key for the device
// with the given hardware-stable clientID, or "" if no device (or no pinned
// key yet) exists for it. Callers use this to detect a device-key mismatch
// *before* calling UpsertDevice — see pairHandler/loginHandler.
func (s *DB) DevicePublicKeyByClientID(clientID string) (string, error) {
	if clientID == "" {
		return "", nil
	}
	var key string
	err := s.db.QueryRow(`SELECT public_key FROM devices WHERE client_id=?`, clientID).Scan(&key)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return key, err
}

// UpsertDevice pairs a device, deduplicating by the hardware-stable clientID.
// If clientID is non-empty and a device with that clientID already exists, its
// token is rotated, it is un-revoked, and its existing id is returned — so a
// phone that re-pairs (after clearing app data, reinstalling, or losing its
// token) reuses its row instead of creating a duplicate. Otherwise a fresh
// device with a new UUID is inserted. Returns the device id to hand back to the
// client. publicKey is pinned on the row (callers must have already checked
// it against DevicePublicKeyByClientID for a mismatch — this does not
// re-check). viaLogin marks the resulting token as owner-trusted (minted by
// /login or /register, i.e. the account password) vs an ordinary /pair
// device — see the via_login column comment in migrate().
func (s *DB) UpsertDevice(clientID, label, token, publicKey string, viaLogin bool) (string, error) {
	hash := hashToken(token)
	now := time.Now().Unix()
	viaLoginInt := 0
	if viaLogin {
		viaLoginInt = 1
	}

	if clientID != "" {
		var existingID string
		err := s.db.QueryRow(
			`SELECT id FROM devices WHERE client_id=?`, clientID,
		).Scan(&existingID)
		if err == nil {
			// Same phone re-pairing: rotate token, clear revoked, refresh label.
			if _, err := s.db.Exec(
				`UPDATE devices SET token_hash=?, label=?, last_seen=?, revoked=0, public_key=?, via_login=? WHERE id=?`,
				hash, label, now, publicKey, viaLoginInt, existingID,
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
		`INSERT INTO devices (id,label,token_hash,created,last_seen,revoked,client_id,public_key,via_login) VALUES (?,?,?,?,?,0,?,?,?)`,
		id, label, hash, now, now, clientID, publicKey, viaLoginInt,
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
		`SELECT id,label,token_hash,created,last_seen,revoked,last_address,last_version,jail_root,read_only,public_key,via_login FROM devices WHERE token_hash=?`, hash,
	)
	d, err := scanDevice(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return d, err
}

// TouchDevice updates last_seen, last_address, and last_version for the given
// id. Called on every authenticated request to record the caller's most
// recent network address and reported app version.
func (s *DB) TouchDevice(id, address, version string) error {
	_, err := s.db.Exec(
		`UPDATE devices SET last_seen=?, last_address=?, last_version=? WHERE id=?`,
		time.Now().Unix(), address, version, id,
	)
	return err
}

func scanDevice(row *sql.Row) (*Device, error) {
	var d Device
	var created, lastSeen int64
	var revoked, readOnly, viaLogin int
	err := row.Scan(&d.ID, &d.Label, &d.TokenHash, &created, &lastSeen, &revoked, &d.LastAddress, &d.LastVersion, &d.JailRoot, &readOnly, &d.PublicKey, &viaLogin)
	if err != nil {
		return nil, err
	}
	d.Created = time.Unix(created, 0)
	d.LastSeen = time.Unix(lastSeen, 0)
	d.Revoked = revoked != 0
	d.ReadOnly = readOnly != 0
	d.ViaLogin = viaLogin != 0
	return &d, nil
}

// rowScanner is satisfied by both *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanDeviceFrom(sc rowScanner) (*Device, error) {
	var d Device
	var created, lastSeen int64
	var revoked, readOnly, viaLogin int
	if err := sc.Scan(&d.ID, &d.Label, &d.TokenHash, &created, &lastSeen, &revoked, &d.LastAddress, &d.LastVersion, &d.JailRoot, &readOnly, &d.PublicKey, &viaLogin); err != nil {
		return nil, err
	}
	d.Created = time.Unix(created, 0)
	d.LastSeen = time.Unix(lastSeen, 0)
	d.Revoked = revoked != 0
	d.ReadOnly = readOnly != 0
	d.ViaLogin = viaLogin != 0
	return &d, nil
}

// ListDevices returns all paired devices (including revoked), oldest first.
func (s *DB) ListDevices() ([]Device, error) {
	rows, err := s.db.Query(
		`SELECT id,label,token_hash,created,last_seen,revoked,last_address,last_version,jail_root,read_only,public_key,via_login FROM devices ORDER BY created`)
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

// GetDeviceByID returns the device with the given id, or (nil,nil) if not found.
func (s *DB) GetDeviceByID(id string) (*Device, error) {
	row := s.db.QueryRow(
		`SELECT id,label,token_hash,created,last_seen,revoked,last_address,last_version,jail_root,read_only,public_key,via_login FROM devices WHERE id=?`, id,
	)
	d, err := scanDevice(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return d, err
}

// SetDeviceJail sets (or clears, if jailRoot is "") the per-device path jail
// for device id (H2). The caller is responsible for validating jailRoot
// before calling this — see setDeviceJailHandler in the server package.
func (s *DB) SetDeviceJail(id, jailRoot string) error {
	_, err := s.db.Exec(`UPDATE devices SET jail_root=? WHERE id=?`, jailRoot, id)
	return err
}

// SetDeviceReadOnly sets (true) or clears (false) the per-device read-only
// flag for device id (#8). A read-only device may browse/download but every
// filesystem write is rejected with READ_ONLY.
func (s *DB) SetDeviceReadOnly(id string, ro bool) error {
	v := 0
	if ro {
		v = 1
	}
	_, err := s.db.Exec(`UPDATE devices SET read_only=? WHERE id=?`, v, id)
	return err
}

// --------- pairing codes ---------

// CreatePairingCode stores a one-time pairing code valid until expires. Stored
// in the DB (not daemon memory) so the `rfe-agent pair` CLI can mint a code the
// running daemon will accept, without a restart. Opportunistically clears
// already-expired codes. jailRoot/readOnly are guest-mode defaults applied to
// the device created when this code is redeemed; pass "", false for a normal
// (non-guest) code.
func (s *DB) CreatePairingCode(code string, expires time.Time, jailRoot string, readOnly bool) error {
	_, _ = s.db.Exec(`DELETE FROM pairing_codes WHERE expires < ?`, time.Now().Unix())
	ro := 0
	if readOnly {
		ro = 1
	}
	_, err := s.db.Exec(
		`INSERT OR REPLACE INTO pairing_codes (code, expires, jail_root, read_only) VALUES (?, ?, ?, ?)`,
		code, expires.Unix(), jailRoot, ro,
	)
	return err
}

// PairingCodeInfo describes a validated one-time pairing code: whether it was
// valid, and any guest-mode defaults (jailRoot/readOnly) to apply to the
// device created when redeeming it.
type PairingCodeInfo struct {
	Valid    bool
	JailRoot string
	ReadOnly bool
}

// ConsumePairingCode validates code and removes it (single-use).
func (s *DB) ConsumePairingCode(code string) PairingCodeInfo {
	if code == "" {
		return PairingCodeInfo{}
	}
	var expires int64
	var jailRoot string
	var readOnly int
	err := s.db.QueryRow(
		`SELECT expires, jail_root, read_only FROM pairing_codes WHERE code=?`, code,
	).Scan(&expires, &jailRoot, &readOnly)
	if err != nil {
		return PairingCodeInfo{}
	}
	// Remove it regardless (single-use); only accept if still valid.
	_, _ = s.db.Exec(`DELETE FROM pairing_codes WHERE code=?`, code)
	if time.Now().Unix() > expires {
		return PairingCodeInfo{}
	}
	return PairingCodeInfo{Valid: true, JailRoot: jailRoot, ReadOnly: readOnly != 0}
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

// --------- users ---------
//
// One account per agent (per PC) — logging in with it grants access to
// everything this agent's device tokens already grant (same authorization
// model as a paired device; login is just an additional way to obtain a
// device token, alongside the existing one-time pairing code). password_hash
// is produced by internal/security's bcrypt wrapper, never stored raw.

// User is an account that can log in from any client (phone or browser) to
// obtain a device token, instead of a one-time pairing code.
type User struct {
	Username     string
	PasswordHash string
	Created      time.Time
}

// CreateUser inserts a new account. Returns an error if the username already
// exists (PRIMARY KEY conflict) — callers should surface that as "already
// set up", not overwrite silently.
func (s *DB) CreateUser(username, passwordHash string) error {
	_, err := s.db.Exec(
		`INSERT INTO users (username,password_hash,created) VALUES (?,?,?)`,
		username, passwordHash, time.Now().Unix(),
	)
	return err
}

// HasAnyUser reports whether at least one account exists on this agent —
// used to enforce the documented one-account-per-agent model at the
// /v1/register gate (CLI `adduser` intentionally bypasses this, for
// headless/scripted setups).
func (s *DB) HasAnyUser() (bool, error) {
	var exists int
	err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM users)`).Scan(&exists)
	return exists != 0, err
}

// GetUserByUsername returns the user, or (nil,nil) if none exists.
func (s *DB) GetUserByUsername(username string) (*User, error) {
	var u User
	var created int64
	err := s.db.QueryRow(
		`SELECT username,password_hash,created FROM users WHERE username=?`, username,
	).Scan(&u.Username, &u.PasswordHash, &created)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	u.Created = time.Unix(created, 0)
	return &u, nil
}

// ListUsers returns all login accounts (never the password hash), newest
// first. RFE has no per-user roles or session tracking, so only the real
// fields — username and created — are returned.
func (s *DB) ListUsers() ([]User, error) {
	rows, err := s.db.Query(`SELECT username,created FROM users ORDER BY created DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []User
	for rows.Next() {
		var u User
		var created int64
		if err := rows.Scan(&u.Username, &created); err != nil {
			return nil, err
		}
		u.Created = time.Unix(created, 0)
		out = append(out, u)
	}
	return out, rows.Err()
}

// ErrLastUser is returned by DeleteUser when username is the only remaining
// login account — deleting it would brick password login entirely (there'd
// be no way to obtain a device token except an existing pairing code).
var ErrLastUser = errors.New("cannot delete the last remaining user")

// DeleteUser permanently removes a login account. Returns ErrLastUser if
// username is the only account, or sql.ErrNoRows if no such account exists.
func (s *DB) DeleteUser(username string) error {
	var count int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&count); err != nil {
		return err
	}
	if count <= 1 {
		return ErrLastUser
	}
	res, err := s.db.Exec(`DELETE FROM users WHERE username=?`, username)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
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
	DeviceID       string
	UpdatedAt      int64 // unix seconds, stamped on each received chunk; 0 = never
}

// CreateTransfer inserts a new transfer row.
func (s *DB) CreateTransfer(t *Transfer) error {
	chunks, _ := json.Marshal([]int{})
	_, err := s.db.Exec(
		`INSERT INTO transfers (id,target_path,total_size,chunk_size,sha256,received_chunks,status,temp_path,total_chunks,device_id)
         VALUES (?,?,?,?,?,?,?,?,?,?)`,
		t.ID, t.TargetPath, t.TotalSize, t.ChunkSize, t.SHA256,
		string(chunks), "open", t.TempPath, t.TotalChunks, t.DeviceID,
	)
	return err
}

// GetTransfer retrieves a transfer by ID.
func (s *DB) GetTransfer(id string) (*Transfer, error) {
	row := s.db.QueryRow(
		`SELECT id,target_path,total_size,chunk_size,sha256,received_chunks,status,temp_path,total_chunks,device_id,updated_at
         FROM transfers WHERE id=?`, id,
	)
	return scanTransfer(row)
}

// MarkChunkReceived atomically records chunk n as received.
//
// The read-modify-write of received_chunks must happen inside a single
// transaction: without one, two concurrent chunk uploads can both read the
// same JSON array, add their own chunk number, and write back — and one
// update silently clobbers the other (lost update).
func (s *DB) MarkChunkReceived(id string, n int) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // no-op once committed

	var chunksJSON string
	if err := tx.QueryRow(
		`SELECT received_chunks FROM transfers WHERE id=?`, id,
	).Scan(&chunksJSON); err != nil {
		return err
	}
	var received []int
	_ = json.Unmarshal([]byte(chunksJSON), &received)

	// Add n if not already present.
	set := make(map[int]struct{}, len(received)+1)
	for _, c := range received {
		set[c] = struct{}{}
	}
	set[n] = struct{}{}
	updated := make([]int, 0, len(set))
	for c := range set {
		updated = append(updated, c)
	}
	// Sort for determinism.
	slices.Sort(updated)
	b, _ := json.Marshal(updated)
	if _, err := tx.Exec(
		`UPDATE transfers SET received_chunks=?, updated_at=? WHERE id=?`,
		string(b), time.Now().Unix(), id,
	); err != nil {
		return err
	}
	return tx.Commit()
}

// SetTransferStatus updates the status of a transfer.
func (s *DB) SetTransferStatus(id, status string) error {
	_, err := s.db.Exec(`UPDATE transfers SET status=? WHERE id=?`, status, id)
	return err
}

// ListTransfers returns the most recent transfer rows, newest first (rowid
// desc — the table has no created column, and rowid is monotonic with insert
// order). Capped at limit because the table accumulates every upload session
// ever opened (mostly stale "open" rows the client never finalized) — the
// web companion only shows recent activity, and the summary counts come from
// CountTransfersByStatus, not len() of this list. deviceID, if non-empty,
// restricts the rows to that device; pass "" for no filter.
func (s *DB) ListTransfers(limit int, deviceID string) ([]Transfer, error) {
	query := `SELECT id,target_path,total_size,chunk_size,sha256,received_chunks,status,temp_path,total_chunks,device_id,updated_at
         FROM transfers`
	args := []any{}
	if deviceID != "" {
		query += ` WHERE device_id=?`
		args = append(args, deviceID)
	}
	query += ` ORDER BY rowid DESC LIMIT ?`
	args = append(args, limit)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Transfer
	for rows.Next() {
		var t Transfer
		var chunksJSON string
		if err := rows.Scan(
			&t.ID, &t.TargetPath, &t.TotalSize, &t.ChunkSize, &t.SHA256,
			&chunksJSON, &t.Status, &t.TempPath, &t.TotalChunks, &t.DeviceID, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		_ = json.Unmarshal([]byte(chunksJSON), &t.ReceivedChunks)
		out = append(out, t)
	}
	return out, rows.Err()
}

// CountTransfersByStatus returns how many transfer rows carry each status
// value (e.g. {"open": 1986, "completed": 3}). Feeds the web companion's
// summary cards so they reflect the whole table, not just the recent page
// ListTransfers returns.
func (s *DB) CountTransfersByStatus() (map[string]int, error) {
	rows, err := s.db.Query(`SELECT status, COUNT(*) FROM transfers GROUP BY status`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]int)
	for rows.Next() {
		var status string
		var n int
		if err := rows.Scan(&status, &n); err != nil {
			return nil, err
		}
		out[status] = n
	}
	return out, rows.Err()
}

// activeTransferWindow bounds how recently a chunk must have landed for an
// "open" transfer to count as genuinely in-flight right now, as opposed to
// one of the thousands of stale never-finalized rows the table accumulates.
// ponytail: fixed window heuristic, not a decay/heartbeat model — revisit if
// slow (multi-minute-per-chunk) transfers need to still read as "active".
const activeTransferWindow = 30 * time.Second

// CountActiveTransfers returns the number of "open" transfers that received
// a chunk within activeTransferWindow — the web companion's "Active now" stat.
func (s *DB) CountActiveTransfers() (int, error) {
	cutoff := time.Now().Add(-activeTransferWindow).Unix()
	var n int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM transfers WHERE status='open' AND updated_at >= ?`,
		cutoff,
	).Scan(&n)
	return n, err
}

// TransferDevice is one entry in the Transfers page's device filter-chip row.
type TransferDevice struct {
	ID    string
	Label string
}

// ListTransferDevices returns the distinct devices that own at least one
// transfer row, labeled via a join against devices (falling back to the raw
// ID if the device was since removed). Rows with no recorded device_id
// (pre-migration transfers) are excluded — the "All" chip already covers them.
func (s *DB) ListTransferDevices() ([]TransferDevice, error) {
	rows, err := s.db.Query(`
        SELECT DISTINCT t.device_id, COALESCE(d.label, t.device_id)
        FROM transfers t LEFT JOIN devices d ON d.id = t.device_id
        WHERE t.device_id != ''
        ORDER BY 2`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []TransferDevice
	for rows.Next() {
		var d TransferDevice
		if err := rows.Scan(&d.ID, &d.Label); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// --------- share tokens (R1) ---------

// ShareToken is an active (unconsumed, unexpired) one-time share link.
type ShareToken struct {
	TokenHash string
	Path      string
	Expires   time.Time
}

// CreateShareToken stores a new one-time share token. tokenHash is the
// SHA-256 hash of the raw token — only the hash is ever persisted.
func (s *DB) CreateShareToken(tokenHash, path string, expiresAt time.Time) error {
	_, err := s.db.Exec(
		`INSERT INTO share_tokens (token_hash, path, created, expires) VALUES (?,?,?,?)`,
		tokenHash, path, time.Now().Unix(), expiresAt.Unix(),
	)
	return err
}

// ConsumeShareToken atomically looks up tokenHash, deletes it (single-use),
// and returns the path it was bound to. ok is false if the token doesn't
// exist or has expired — callers must not distinguish the two in their
// response (don't leak which).
func (s *DB) ConsumeShareToken(tokenHash string) (path string, ok bool, err error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", false, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // no-op once committed

	var expires int64
	err = tx.QueryRow(
		`SELECT path, expires FROM share_tokens WHERE token_hash=?`, tokenHash,
	).Scan(&path, &expires)
	if err == sql.ErrNoRows {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}

	if _, err := tx.Exec(`DELETE FROM share_tokens WHERE token_hash=?`, tokenHash); err != nil {
		return "", false, err
	}
	if err := tx.Commit(); err != nil {
		return "", false, err
	}

	if time.Now().Unix() > expires {
		return "", false, nil
	}
	return path, true, nil
}

// DeleteShareToken removes a share token (explicit revoke), regardless of
// whether it has expired.
func (s *DB) DeleteShareToken(tokenHash string) error {
	_, err := s.db.Exec(`DELETE FROM share_tokens WHERE token_hash=?`, tokenHash)
	return err
}

// ListShareTokens returns all active (unexpired) share tokens.
func (s *DB) ListShareTokens() ([]ShareToken, error) {
	rows, err := s.db.Query(
		`SELECT token_hash, path, expires FROM share_tokens WHERE expires >= ? ORDER BY created`,
		time.Now().Unix(),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []ShareToken
	for rows.Next() {
		var t ShareToken
		var expires int64
		if err := rows.Scan(&t.TokenHash, &t.Path, &expires); err != nil {
			return nil, err
		}
		t.Expires = time.Unix(expires, 0)
		out = append(out, t)
	}
	return out, rows.Err()
}

// LogShareMint records a share token's minting in the audit log.
func (s *DB) LogShareMint(tokenHash, path string, expiresAt time.Time) error {
	_, err := s.db.Exec(
		`INSERT INTO share_log (token_hash, path, minted_at, expires_at) VALUES (?,?,?,?)`,
		tokenHash, path, time.Now().Unix(), expiresAt.Unix(),
	)
	return err
}

// LogShareServed records that a share token was successfully served, by
// stamping served_at + requesterIP on its most recent (served_at IS NULL)
// mint row.
func (s *DB) LogShareServed(tokenHash, requesterIP string) error {
	_, err := s.db.Exec(
		`UPDATE share_log SET served_at=?, requester_ip=?
         WHERE id = (SELECT id FROM share_log WHERE token_hash=? AND served_at IS NULL ORDER BY id DESC LIMIT 1)`,
		time.Now().Unix(), requesterIP, tokenHash,
	)
	return err
}

// SweepExpiredShareTokens deletes every share token whose expiry has passed
// and returns the number of rows removed. Called periodically by a
// background goroutine (see cmd/agent/main.go).
func (s *DB) SweepExpiredShareTokens() (int, error) {
	res, err := s.db.Exec(`DELETE FROM share_tokens WHERE expires < ?`, time.Now().Unix())
	if err != nil {
		return 0, err
	}
	n, err := res.RowsAffected()
	return int(n), err
}

func scanTransfer(row *sql.Row) (*Transfer, error) {
	var t Transfer
	var chunksJSON string
	err := row.Scan(
		&t.ID, &t.TargetPath, &t.TotalSize, &t.ChunkSize, &t.SHA256,
		&chunksJSON, &t.Status, &t.TempPath, &t.TotalChunks, &t.DeviceID, &t.UpdatedAt,
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
