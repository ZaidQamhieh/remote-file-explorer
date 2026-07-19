package main

import "testing"

// TestWebListenBindAddr is the PR-61 regression: an operator restricting the
// primary listener to a specific host must have the best-effort port-443
// listener inherit that restriction, not always bind all interfaces.
func TestWebListenBindAddr(t *testing.T) {
	cases := []struct {
		name    string
		primary string
		want    string
	}{
		{"no host: all interfaces", ":8765", webListenAddr},
		{"explicit loopback carries over", "127.0.0.1:8765", "127.0.0.1:443"},
		{"explicit LAN IP carries over", "192.168.1.5:8765", "192.168.1.5:443"},
		{"unparsable falls back to all interfaces", "not-an-addr", webListenAddr},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := webListenBindAddr(tc.primary); got != tc.want {
				t.Fatalf("webListenBindAddr(%q) = %q, want %q", tc.primary, got, tc.want)
			}
		})
	}
}
