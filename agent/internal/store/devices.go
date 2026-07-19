package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

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
// device — see the via_login column comment in migrateBaseline().
func (s *DB) UpsertDevice(clientID, label, token, publicKey string, viaLogin bool) (string, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	id, err := upsertDeviceTx(tx, clientID, label, token, publicKey, viaLogin)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return id, nil
}

// upsertDeviceTx is UpsertDevice's body, factored out so the account
// workflows can run it inside their own transaction rather than as a separate
// one (PR-45).
//
// PR-44: the find-or-create is one transaction so two concurrent pairings of
// the same client_id can't both insert (the partial unique index is the
// DB-level backstop).
func upsertDeviceTx(tx *sql.Tx, clientID, label, token, publicKey string, viaLogin bool) (string, error) {
	hash := hashToken(token)
	now := time.Now().Unix()
	viaLoginInt := 0
	if viaLogin {
		viaLoginInt = 1
	}

	if clientID != "" {
		var existingID string
		err := tx.QueryRow(
			`SELECT id FROM devices WHERE client_id=?`, clientID,
		).Scan(&existingID)
		if err == nil {
			// Same phone re-pairing: rotate token, clear revoked, refresh label.
			if _, err := tx.Exec(
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
	if _, err := tx.Exec(
		`INSERT INTO devices (id,label,token_hash,created,last_seen,revoked,client_id,public_key,via_login) VALUES (?,?,?,?,?,0,?,?,?)`,
		id, label, hash, now, now, clientID, publicKey, viaLoginInt,
	); err != nil {
		return "", err
	}
	return id, nil
}

// ErrAccountExists is returned by RegisterAccount when this computer already
// has a login account. RFE allows exactly one.
var ErrAccountExists = errors.New("an account already exists")

// RegisterAccount creates the computer's single login account and the
// registering device together, in one transaction (PR-45).
//
// Split across separate calls, as this used to be, the "exactly one account"
// rule was decided by a SELECT that another registration could invalidate
// before the INSERT landed, and a failure between the two left an account with
// no device — with the pairing code already burned, so nobody could retry.
func (s *DB) RegisterAccount(clientID, label, token, publicKey, username, passwordHash string) (string, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	var users int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&users); err != nil {
		return "", err
	}
	if users > 0 {
		return "", ErrAccountExists
	}
	if _, err := tx.Exec(
		`INSERT INTO users (username,password_hash,created) VALUES (?,?,?)`,
		username, passwordHash, time.Now().Unix(),
	); err != nil {
		return "", err
	}
	deviceID, err := upsertDeviceTx(tx, clientID, label, token, publicKey, true)
	if err != nil {
		return "", err
	}
	if _, err := tx.Exec(`UPDATE devices SET username=? WHERE id=?`, username, deviceID); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return deviceID, nil
}

// LoginDevice records a successful password login: the device row and the
// account that authenticated it land together, so a failure can't leave a
// usable token stamped with no username (PR-45).
func (s *DB) LoginDevice(clientID, label, token, publicKey, username string) (string, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()

	deviceID, err := upsertDeviceTx(tx, clientID, label, token, publicKey, true)
	if err != nil {
		return "", err
	}
	if _, err := tx.Exec(`UPDATE devices SET username=? WHERE id=?`, username, deviceID); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return deviceID, nil
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
	// PR-41: skip the write if this device was touched within touchInterval.
	now := time.Now()
	s.touchMu.Lock()
	if last, ok := s.lastTouch[id]; ok && now.Sub(last) < touchInterval {
		s.touchMu.Unlock()
		return nil
	}
	s.lastTouch[id] = now
	s.touchMu.Unlock()

	_, err := s.db.Exec(
		`UPDATE devices SET last_seen=?, last_address=?, last_version=? WHERE id=?`,
		now.Unix(), address, version, id,
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
	// PR-10: consume the code atomically. DELETE ... RETURNING guarantees only
	// one concurrent caller can claim a single-use code — a SELECT-then-DELETE
	// race let two requests both validate before either deleted.
	err := s.db.QueryRow(
		`DELETE FROM pairing_codes WHERE code=? RETURNING expires, jail_root, read_only`, code,
	).Scan(&expires, &jailRoot, &readOnly)
	if err != nil {
		return PairingCodeInfo{}
	}
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
