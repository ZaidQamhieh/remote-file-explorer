// Package server — list endpoints (plus user removal) backing the web
// companion's Transfers, Users, and Logs pages. All three surface data RFE
// genuinely has (upload sessions, login accounts, the agent's own journald
// output) — none is synthesized.
package server

import (
	"database/sql"
	"errors"
	"net/http"
	"os/exec"
	"path"
	"regexp"
	"sort"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// goLogPrefix matches the "2006/01/02 15:04:05 " stamp Go's log.Printf
// prepends by default — redundant with journald's own timestamp, so it's
// stripped from the message for the Logs page.
var goLogPrefix = regexp.MustCompile(`^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} `)

// --------- GET /transfers/list ---------

// maxTransferRows caps how many recent transfer rows the list returns. The
// table accumulates every upload session ever opened (thousands of stale
// "open" rows the client never finalized), so the page shows recent activity
// only; the summary counts come from the full-table aggregate below.
const maxTransferRows = 200

func listTransfersHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		deviceFilter := r.URL.Query().Get("device")
		userFilter := r.URL.Query().Get("user")
		transfers, err := db.ListTransfers(maxTransferRows, deviceFilter, userFilter)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		counts, err := db.CountTransfersByStatus()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		activeNow, err := db.CountActiveTransfers()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		transferDevices, err := db.ListTransferDevices()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		devices := make([]map[string]any, 0, len(transferDevices))
		for _, d := range transferDevices {
			devices = append(devices, map[string]any{"id": d.ID, "label": d.Label})
		}
		accounts, err := db.ListUsers()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		users := make([]string, 0, len(accounts))
		for _, u := range accounts {
			users = append(users, u.Username)
		}
		sort.Strings(users)
		total := 0
		for _, n := range counts {
			total += n
		}
		rows := make([]map[string]any, 0, len(transfers))
		for _, t := range transfers {
			received := len(t.ReceivedChunks)
			var progress float64
			if t.TotalChunks > 0 {
				progress = float64(received) / float64(t.TotalChunks) * 100
			}
			// receivedBytes is an estimate: full chunks received × chunkSize,
			// capped at the real total (the final chunk is usually smaller).
			receivedBytes := int64(received) * int64(t.ChunkSize)
			if receivedBytes > t.TotalSize {
				receivedBytes = t.TotalSize
			}
			rows = append(rows, map[string]any{
				"id":            t.ID,
				"name":          path.Base(t.TargetPath),
				"path":          t.TargetPath,
				"totalSize":     t.TotalSize,
				"receivedBytes": receivedBytes,
				"progress":      progress,
				"status":        t.Status,    // open | completed | failed
				"deviceId":      t.DeviceID,  // "" on rows created before the device_id migration
				"updatedAt":     t.UpdatedAt, // unix seconds, stamped per received chunk; 0 = never
			})
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"total":     total,
			"counts":    counts,    // status -> count, whole table
			"transfers": rows,      // most recent maxTransferRows only
			"activeNow": activeNow, // open transfers that received a chunk recently
			"devices":   devices,   // distinct devices with at least one transfer, for the filter-chip row
			"users":     users,     // distinct login accounts with at least one transfer, for the user filter-chip row
		})
	}
}

// --------- GET /users ---------

func listUsersHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		users, err := db.ListUsers()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		out := make([]map[string]any, 0, len(users))
		for _, u := range users {
			out = append(out, map[string]any{
				"username": u.Username,
				"created":  u.Created.Unix(),
			})
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// --------- DELETE /users/{username} ---------

// deleteUserHandler removes a login account. Every account is a full admin
// today (see store.User), so there's no self-vs-other distinction like
// device management has — any authenticated caller may remove any account,
// except the last one (see store.ErrLastUser), which would brick password
// login entirely.
func deleteUserHandler(db *store.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		username := chi.URLParam(r, "username")
		err := db.DeleteUser(username)
		switch {
		case err == nil:
			w.WriteHeader(http.StatusNoContent)
		case errors.Is(err, store.ErrLastUser):
			writeError(w, http.StatusBadRequest, "LAST_USER", "cannot delete the only remaining login account")
		case errors.Is(err, sql.ErrNoRows):
			writeError(w, http.StatusNotFound, "NOT_FOUND", "no such user")
		default:
			writeError(w, http.StatusInternalServerError, "INTERNAL", err.Error())
		}
	}
}

// --------- GET /logs ---------

// maxLogLines caps how much of the journal the logs endpoint returns.
const maxLogLines = 200

// listLogsHandler tails the agent's own journald output. This exposes no
// more than a paired device can already see (it can read any file); the
// agent's log is strictly less sensitive. Linux/systemd only — returns an
// empty list elsewhere rather than erroring.
func listLogsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cmd := exec.Command("journalctl", "--user", "-u", "rfe-agent.service",
			"-n", "200", "--no-pager", "-o", "short-iso")
		raw, err := cmd.Output()
		if err != nil {
			// No journald (non-systemd, or not run as a unit): honestly empty.
			writeJSON(w, http.StatusOK, []map[string]any{})
			return
		}
		lines := strings.Split(strings.TrimRight(string(raw), "\n"), "\n")
		if len(lines) > maxLogLines {
			lines = lines[len(lines)-maxLogLines:]
		}
		out := make([]map[string]any, 0, len(lines))
		for _, line := range lines {
			ts, msg := splitLogLine(line)
			out = append(out, map[string]any{"ts": ts, "message": msg})
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// splitLogLine parses a `short-iso` journald line
// ("2006-01-02T15:04:05+ZZ:ZZ host rfe-agent[pid]: message") into the
// timestamp and the message. RFE's logs are plain log.Printf output with no
// severity level, so no level is inferred. Falls back to the whole line as
// the message if the shape doesn't match.
func splitLogLine(line string) (ts, msg string) {
	fields := strings.SplitN(line, " ", 2)
	if len(fields) < 2 {
		return "", line
	}
	ts = fields[0]
	rest := fields[1]
	// Drop the "host rfe-agent[pid]: " prefix if present.
	if i := strings.Index(rest, ": "); i >= 0 {
		rest = rest[i+2:]
	}
	return ts, goLogPrefix.ReplaceAllString(rest, "")
}
