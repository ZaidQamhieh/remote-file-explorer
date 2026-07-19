package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// --------- transfers ---------

// Transfer is an in-progress or completed upload session.
type Transfer struct {
	ID             string
	TargetPath     string
	TotalSize      int64
	ChunkSize      int
	SHA256         string
	ReceivedChunks []int  // populated by ChunkNumbers on the resume path only
	ReceivedCount  int    // how many chunks landed; cheap aggregate, always set
	Status         string // open | completed | failed
	TempPath       string
	TotalChunks    int
	DeviceID       string
	UpdatedAt      int64 // unix seconds, stamped on each received chunk; 0 = never
	Overwrite      bool  // may Complete replace an existing target? (PR-50)
}

// ExpectedChunkLen returns exactly how many bytes chunk n must carry: a full
// ChunkSize for every chunk but the last, and the remainder for the last one.
// A zero-length transfer has one empty chunk. Out-of-range n returns -1, which
// no chunk length can equal.
func (t *Transfer) ExpectedChunkLen(n int) int {
	if n < 0 || n >= t.TotalChunks {
		return -1
	}
	if t.ChunkSize <= 0 {
		return -1
	}
	remaining := t.TotalSize - int64(n)*int64(t.ChunkSize)
	if remaining < 0 {
		return -1
	}
	if remaining > int64(t.ChunkSize) {
		return t.ChunkSize
	}
	return int(remaining)
}

// CreateTransfer inserts a new transfer row.
func (s *DB) CreateTransfer(t *Transfer) error {
	_, err := s.db.Exec(
		`INSERT INTO transfers (id,target_path,total_size,chunk_size,sha256,status,temp_path,total_chunks,device_id,overwrite)
         VALUES (?,?,?,?,?,?,?,?,?,?)`,
		t.ID, t.TargetPath, t.TotalSize, t.ChunkSize, t.SHA256,
		"open", t.TempPath, t.TotalChunks, t.DeviceID, t.Overwrite,
	)
	return err
}

// GetTransfer retrieves a transfer by ID.
func (s *DB) GetTransfer(id string) (*Transfer, error) {
	row := s.db.QueryRow(
		`SELECT id,target_path,total_size,chunk_size,sha256,status,temp_path,total_chunks,device_id,updated_at,overwrite,
                (SELECT COUNT(*) FROM transfer_chunks c WHERE c.transfer_id=transfers.id)
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

	// The transfer must exist: an INSERT against a deleted session would
	// otherwise silently resurrect chunk rows nothing ever cleans up.
	var exists int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM transfers WHERE id=?`, id).Scan(&exists); err != nil {
		return err
	}
	if exists == 0 {
		return sql.ErrNoRows
	}
	// OR IGNORE makes a re-sent chunk a no-op rather than an error: the
	// primary key is the idempotency, so there is no read-modify-write left to
	// lose an update (PR-42).
	if _, err := tx.Exec(
		`INSERT OR IGNORE INTO transfer_chunks (transfer_id, chunk_no) VALUES (?,?)`, id, n,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(
		`UPDATE transfers SET updated_at=? WHERE id=?`, time.Now().Unix(), id,
	); err != nil {
		return err
	}
	return tx.Commit()
}

// HasChunk reports whether chunk n of this transfer has been received. An
// indexed point lookup — the caller must not load every chunk to answer it.
func (s *DB) HasChunk(id string, n int) (bool, error) {
	var found int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM transfer_chunks WHERE transfer_id=? AND chunk_no=?`, id, n,
	).Scan(&found)
	return found > 0, err
}

// ChunkNumbers returns the received chunk numbers, ascending. Used for the
// resume path, which genuinely needs the whole set; per-chunk callers want
// HasChunk instead.
func (s *DB) ChunkNumbers(id string) ([]int, error) {
	rows, err := s.db.Query(
		`SELECT chunk_no FROM transfer_chunks WHERE transfer_id=? ORDER BY chunk_no`, id,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []int
	for rows.Next() {
		var n int
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// SetTransferStatus updates the status of a transfer.
func (s *DB) SetTransferStatus(id, status string) error {
	_, err := s.db.Exec(`UPDATE transfers SET status=? WHERE id=?`, status, id)
	return err
}

// DeleteTransfer removes a transfer row (its own history, not the uploaded
// file). Used by the web companion to clear stale "open" or "failed" rows —
// the table otherwise accumulates every session ever opened forever.
func (s *DB) DeleteTransfer(id string) error {
	// Chunk rows are keyed by transfer_id with no foreign key, so they must be
	// cleared explicitly or they outlive the session forever (PR-42).
	if _, err := s.db.Exec(`DELETE FROM transfer_chunks WHERE transfer_id=?`, id); err != nil {
		return err
	}
	res, err := s.db.Exec(`DELETE FROM transfers WHERE id=?`, id)
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

// ListTransfers returns the most recent transfer rows, newest first (rowid
// desc — the table has no created column, and rowid is monotonic with insert
// order). Capped at limit because the table accumulates every upload session
// ever opened (mostly stale "open" rows the client never finalized) — the
// web companion only shows recent activity, and the summary counts come from
// CountTransfersByStatus, not len() of this list. deviceID, if non-empty,
// restricts the rows to that device; username, if non-empty, restricts them
// to devices stamped with that login account; pass "" for no filter.
func (s *DB) ListTransfers(limit int, deviceID, username string) ([]Transfer, error) {
	query := `SELECT id,target_path,total_size,chunk_size,sha256,status,temp_path,total_chunks,device_id,updated_at,overwrite,
                 (SELECT COUNT(*) FROM transfer_chunks c WHERE c.transfer_id=transfers.id)
          FROM transfers`
	args := []any{}
	var where []string
	if deviceID != "" {
		where = append(where, `device_id=?`)
		args = append(args, deviceID)
	}
	if username != "" {
		where = append(where, `device_id IN (SELECT id FROM devices WHERE username=?)`)
		args = append(args, username)
	}
	if len(where) > 0 {
		query += ` WHERE ` + strings.Join(where, ` AND `)
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
		if err := rows.Scan(
			&t.ID, &t.TargetPath, &t.TotalSize, &t.ChunkSize, &t.SHA256,
			&t.Status, &t.TempPath, &t.TotalChunks, &t.DeviceID, &t.UpdatedAt, &t.Overwrite,
			&t.ReceivedCount,
		); err != nil {
			return nil, err
		}
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

// ActiveTransferWindow bounds how recently a chunk must have landed for an
// "open" transfer to count as genuinely in-flight right now, as opposed to
// one of the thousands of stale never-finalized rows the table accumulates.
// ponytail: fixed window heuristic, not a decay/heartbeat model — revisit if
// slow (multi-minute-per-chunk) transfers need to still read as "active".
const ActiveTransferWindow = 30 * time.Second

// CountActiveTransfers returns the number of "open" transfers that received
// a chunk within ActiveTransferWindow — the web companion's "Active now" stat.
func (s *DB) CountActiveTransfers() (int, error) {
	cutoff := time.Now().Add(-ActiveTransferWindow).Unix()
	var n int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM transfers WHERE status='open' AND updated_at >= ?`,
		cutoff,
	).Scan(&n)
	return n, err
}

// TransferDevice is one entry in the Transfers page's device filter-chip row
// (and the table's Device/User columns).
type TransferDevice struct {
	ID       string
	Label    string
	Username string // "" if the device paired by code rather than login
}

// ListTransferDevices returns the distinct devices that own at least one
// transfer row, labeled via a join against devices (falling back to the raw
// ID if the device was since removed). Rows with no recorded device_id
// (pre-migration transfers) are excluded — the "All" chip already covers them.
func (s *DB) ListTransferDevices() ([]TransferDevice, error) {
	rows, err := s.db.Query(`
        SELECT DISTINCT t.device_id, COALESCE(d.label, t.device_id), COALESCE(d.username, '')
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
		if err := rows.Scan(&d.ID, &d.Label, &d.Username); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// scanTransfer reads a transfer row. ReceivedChunks is deliberately NOT
// populated: loading every chunk number to answer "is chunk n here?" is the
// quadratic behaviour PR-42 removed. Callers that need the set ask
// ChunkNumbers; ReceivedCount covers the rest.
func scanTransfer(row *sql.Row) (*Transfer, error) {
	var t Transfer
	err := row.Scan(
		&t.ID, &t.TargetPath, &t.TotalSize, &t.ChunkSize, &t.SHA256,
		&t.Status, &t.TempPath, &t.TotalChunks, &t.DeviceID, &t.UpdatedAt, &t.Overwrite,
		&t.ReceivedCount,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}
