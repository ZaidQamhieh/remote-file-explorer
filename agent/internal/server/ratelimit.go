// Package server — simple in-memory rate limiting for unauthenticated routes.
package server

import (
	"net"
	"net/http"
	"sync"
	"time"
)

// clientIP returns the caller's source IP from RemoteAddr. It deliberately
// ignores X-Forwarded-For: that header is client-controlled and trusting it
// would let an attacker forge a fresh key per request (PR-52).
func clientIP(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// keyedLimiter applies a per-key fixed window so one source can't consume the
// whole endpoint's budget for everyone (PR-52). The key map is bounded and
// lazily pruned of fully-expired windows to cap memory.
type keyedLimiter struct {
	mu          sync.Mutex
	maxAttempts int
	window      time.Duration
	perKey      map[string]*fixedWindowLimiter
	maxKeys     int
}

func newKeyedLimiter(maxAttempts int, window time.Duration) *keyedLimiter {
	return &keyedLimiter{
		maxAttempts: maxAttempts,
		window:      window,
		perKey:      make(map[string]*fixedWindowLimiter),
		maxKeys:     4096,
	}
}

// Allow reports whether an attempt from key is permitted, recording it if so.
func (k *keyedLimiter) Allow(key string) bool {
	k.mu.Lock()
	defer k.mu.Unlock()
	l, ok := k.perKey[key]
	if !ok {
		if len(k.perKey) >= k.maxKeys {
			k.pruneLocked()
		}
		l = newFixedWindowLimiter(k.maxAttempts, k.window)
		k.perKey[key] = l
	}
	return l.Allow()
}

// pruneLocked drops per-key limiters whose window holds no recent hits.
func (k *keyedLimiter) pruneLocked() {
	now := time.Now()
	for key, l := range k.perKey {
		l.mu.Lock()
		cutoff := now.Add(-l.window)
		active := false
		for _, t := range l.hits {
			if t.After(cutoff) {
				active = true
				break
			}
		}
		l.mu.Unlock()
		if !active {
			delete(k.perKey, key)
		}
	}
}

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
