// Package settings holds the agent's live-mutable configuration (read-only
// mode, the folder jail, and the display name), persisted in the config table
// so changes made from the phone take effect immediately without a restart.
package settings

import (
	"path/filepath"
	"strings"
	"sync"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

const (
	keyReadOnly  = "readOnly"
	keyRoots     = "roots"
	keyAgentName = "agentName"
)

// Store is a concurrency-safe view over the agent's settings.
type Store struct {
	db        *store.DB
	mu        sync.RWMutex
	readOnly  bool
	roots     []string
	agentName string
}

// Load builds a Store. Any config key that is unset is seeded from the
// provided default (typically a CLI flag) and written back; once a key exists
// in the DB, the persisted value wins on every subsequent load.
func Load(db *store.DB, seedReadOnly bool, seedRoots []string, seedName string) (*Store, error) {
	s := &Store{db: db}

	ro, err := db.GetConfig(keyReadOnly)
	if err != nil {
		return nil, err
	}
	if ro == "" {
		s.readOnly = seedReadOnly
		if err := db.SetConfig(keyReadOnly, boolToStr(seedReadOnly)); err != nil {
			return nil, err
		}
	} else {
		s.readOnly = ro == "true"
	}

	rts, err := db.GetConfig(keyRoots)
	if err != nil {
		return nil, err
	}
	if rts == "" {
		s.roots = normalizeRoots(seedRoots)
		if err := db.SetConfig(keyRoots, joinRoots(s.roots)); err != nil {
			return nil, err
		}
	} else {
		s.roots = splitRoots(rts)
	}

	nm, err := db.GetConfig(keyAgentName)
	if err != nil {
		return nil, err
	}
	if nm == "" {
		s.agentName = seedName
		if err := db.SetConfig(keyAgentName, seedName); err != nil {
			return nil, err
		}
	} else {
		s.agentName = nm
	}

	return s, nil
}

// IsReadOnly reports whether writes are currently rejected.
func (s *Store) IsReadOnly() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.readOnly
}

// Roots returns a copy of the current jail roots (empty = allow all).
func (s *Store) Roots() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]string, len(s.roots))
	copy(out, s.roots)
	return out
}

// AgentName returns the current display name.
func (s *Store) AgentName() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.agentName
}

// SetReadOnly persists and applies the read-only flag.
func (s *Store) SetReadOnly(v bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyReadOnly, boolToStr(v)); err != nil {
		return err
	}
	s.readOnly = v
	return nil
}

// SetRoots normalizes, persists, and applies the jail roots.
func (s *Store) SetRoots(roots []string) error {
	norm := normalizeRoots(roots)
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyRoots, joinRoots(norm)); err != nil {
		return err
	}
	s.roots = norm
	return nil
}

// SetAgentName persists and applies the display name.
func (s *Store) SetAgentName(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.db.SetConfig(keyAgentName, name); err != nil {
		return err
	}
	s.agentName = name
	return nil
}

func boolToStr(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// roots are stored newline-joined (paths may contain commas but not newlines).
func joinRoots(roots []string) string { return strings.Join(roots, "\n") }

func splitRoots(v string) []string {
	return normalizeRoots(strings.Split(v, "\n"))
}

func normalizeRoots(in []string) []string {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, r := range in {
		r = strings.TrimSpace(r)
		if r == "" {
			continue
		}
		c := filepath.Clean(r)
		if _, dup := seen[c]; dup {
			continue
		}
		seen[c] = struct{}{}
		out = append(out, c)
	}
	return out
}
