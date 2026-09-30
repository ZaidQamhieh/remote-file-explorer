package store

import (
	"database/sql"
	"errors"
	"time"
)

// A pair request is a phone asking to be paired; the owner approves or rejects
// it at the PC. Statuses: pending, approved (decided, token not yet collected),
// rejected, done (token collected).
const (
	PairPending  = "pending"
	PairApproved = "approved"
	PairRejected = "rejected"
	PairDone     = "done"
)

// MaxPendingPairRequests bounds how many undecided requests can exist at once,
// so an unauthenticated peer cannot bury the owner in prompts.
const MaxPendingPairRequests = 3

// ErrTooManyPairRequests means MaxPendingPairRequests undecided requests already exist.
var ErrTooManyPairRequests = errors.New("too many pending pair requests")

// ErrPairRequestGone means the request does not exist, expired, or was already decided.
var ErrPairRequestGone = errors.New("pair request not found or already decided")

type PairRequest struct {
	ID          string
	Label       string
	ClientID    string
	PublicKey   string
	ClientNonce string
	RemoteIP    string
	Status      string
	Created     int64
	Expires     int64
}

// CreatePairRequest stores a new pending request. Expired rows are pruned first.
func (s *DB) CreatePairRequest(r PairRequest) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	now := time.Now().Unix()
	if _, err := tx.Exec(`DELETE FROM pair_requests WHERE expires < ? OR (status IN ('rejected','done') AND created < ?)`, now, now-600); err != nil {
		return err
	}
	var pending int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM pair_requests WHERE status='pending' AND expires >= ?`, now).Scan(&pending); err != nil {
		return err
	}
	if pending >= MaxPendingPairRequests {
		return ErrTooManyPairRequests
	}
	if _, err := tx.Exec(
		`INSERT INTO pair_requests (id,label,client_id,public_key,client_nonce,remote_ip,status,created,expires) VALUES (?,?,?,?,?,?,?,?,?)`,
		r.ID, r.Label, r.ClientID, r.PublicKey, r.ClientNonce, r.RemoteIP, PairPending, r.Created, r.Expires,
	); err != nil {
		return err
	}
	return tx.Commit()
}

const pairRequestCols = `id,label,client_id,public_key,client_nonce,remote_ip,status,created,expires`

func scanPairRequest(row interface{ Scan(...any) error }) (PairRequest, error) {
	var r PairRequest
	err := row.Scan(&r.ID, &r.Label, &r.ClientID, &r.PublicKey, &r.ClientNonce, &r.RemoteIP, &r.Status, &r.Created, &r.Expires)
	return r, err
}

// GetPairRequest returns a request by id; ok is false when it is unknown or expired while undecided.
func (s *DB) GetPairRequest(id string) (PairRequest, bool, error) {
	r, err := scanPairRequest(s.db.QueryRow(`SELECT `+pairRequestCols+` FROM pair_requests WHERE id=?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return PairRequest{}, false, nil
	}
	if err != nil {
		return PairRequest{}, false, err
	}
	if r.Status == PairPending && r.Expires < time.Now().Unix() {
		return PairRequest{}, false, nil
	}
	return r, true, nil
}

// ListPendingPairRequests returns the undecided, unexpired requests, oldest first.
func (s *DB) ListPendingPairRequests() ([]PairRequest, error) {
	rows, err := s.db.Query(`SELECT `+pairRequestCols+` FROM pair_requests WHERE status='pending' AND expires >= ? ORDER BY created`, time.Now().Unix())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PairRequest
	for rows.Next() {
		r, err := scanPairRequest(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// DecidePairRequest approves or rejects a pending, unexpired request.
func (s *DB) DecidePairRequest(id string, approve bool) error {
	status := PairRejected
	if approve {
		status = PairApproved
	}
	res, err := s.db.Exec(`UPDATE pair_requests SET status=? WHERE id=? AND status='pending' AND expires >= ?`, status, id, time.Now().Unix())
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrPairRequestGone
	}
	return nil
}

// ClaimApprovedPairRequest moves an approved request to done exactly once and
// returns it, so the device token is minted for one poll only.
func (s *DB) ClaimApprovedPairRequest(id string) (PairRequest, bool, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return PairRequest{}, false, err
	}
	defer func() { _ = tx.Rollback() }()
	res, err := tx.Exec(`UPDATE pair_requests SET status='done' WHERE id=? AND status='approved'`, id)
	if err != nil {
		return PairRequest{}, false, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return PairRequest{}, false, nil
	}
	r, err := scanPairRequest(tx.QueryRow(`SELECT `+pairRequestCols+` FROM pair_requests WHERE id=?`, id))
	if err != nil {
		return PairRequest{}, false, err
	}
	return r, true, tx.Commit()
}
