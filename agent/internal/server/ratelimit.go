// Package server — simple in-memory rate limiting for unauthenticated routes.
package server

import (
	"sync"
	"time"
)

// fixedWindowLimiter is a minimal global fixed-window rate limiter: it allows
// up to maxAttempts within a rolling window of length window. It's
// intentionally simple (no external deps) and suited to a single-user agent
// guarding a low-traffic endpoint like /v1/pair against brute force.
type fixedWindowLimiter struct {
	mu          sync.Mutex
	maxAttempts int
	window      time.Duration
	hits        []time.Time
}

// newFixedWindowLimiter creates a limiter allowing maxAttempts per window.
func newFixedWindowLimiter(maxAttempts int, window time.Duration) *fixedWindowLimiter {
	return &fixedWindowLimiter{maxAttempts: maxAttempts, window: window}
}

// Allow reports whether a new attempt is permitted under the current window,
// recording it if so.
func (l *fixedWindowLimiter) Allow() bool {
	return l.allowAt(time.Now())
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
