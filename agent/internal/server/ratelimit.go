// Package server — simple in-memory rate limiting for unauthenticated routes.
package server

import (
	"net"
	"net/http"
	"sync"
	"time"
)

const maxRateLimitKeys = 1024

// fixedWindowLimiter enforces a per-source window plus a wider global ceiling.
// The bounded key map prevents spoofed source addresses from growing memory
// indefinitely.
type fixedWindowLimiter struct {
	mu          sync.Mutex
	maxAttempts int
	window      time.Duration
	hits        []time.Time
	keyedHits   map[string][]time.Time
}

// newFixedWindowLimiter creates a limiter allowing maxAttempts per window.
func newFixedWindowLimiter(maxAttempts int, window time.Duration) *fixedWindowLimiter {
	return &fixedWindowLimiter{
		maxAttempts: maxAttempts,
		window:      window,
		keyedHits:   make(map[string][]time.Time),
	}
}

// Allow reports whether a new attempt is permitted under the current window,
// recording it if so.
func (l *fixedWindowLimiter) Allow() bool {
	return l.allowAt(time.Now())
}

// AllowRequest applies the per-source limiter using only the transport peer
// address. Forwarded headers are intentionally ignored because the agent does
// not configure a trusted reverse-proxy boundary.
func (l *fixedWindowLimiter) AllowRequest(r *http.Request) bool {
	key := r.RemoteAddr
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		key = host
	}
	if key == "" {
		key = "unknown"
	}
	return l.allowKeyAt(key, time.Now())
}

// allowAt is the testable core of Allow, parameterized on "now".
func (l *fixedWindowLimiter) allowAt(now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	cutoff := now.Add(-l.window)
	kept := l.hits[:0]
	for _, t := range l.hits {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	l.hits = kept

	if len(l.hits) >= l.maxAttempts {
		return false
	}
	l.hits = append(l.hits, now)
	return true
}

func (l *fixedWindowLimiter) allowKeyAt(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	cutoff := now.Add(-l.window)
	l.hits = pruneHits(l.hits, cutoff)
	keyHits := pruneHits(l.keyedHits[key], cutoff)
	if len(keyHits) == 0 {
		delete(l.keyedHits, key)
	}

	// Ten full per-source bursts may pass within one window, but one source
	// cannot consume another source's allocation.
	if len(l.hits) >= l.maxAttempts*10 || len(keyHits) >= l.maxAttempts {
		return false
	}
	if _, exists := l.keyedHits[key]; !exists && len(l.keyedHits) >= maxRateLimitKeys {
		return false
	}
	l.hits = append(l.hits, now)
	l.keyedHits[key] = append(keyHits, now)
	return true
}

func pruneHits(hits []time.Time, cutoff time.Time) []time.Time {
	kept := hits[:0]
	for _, hit := range hits {
		if hit.After(cutoff) {
			kept = append(kept, hit)
		}
	}
	return kept
}
