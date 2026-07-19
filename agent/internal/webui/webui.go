// Package webui serves the browser-based web companion (agent control,
// status, settings) as a static bundle embedded in the agent binary — one
// binary, one port, no separate hosting step. Vanilla JS/HTML, no build
// tool for markup: dist/index.html is served as-is. Styling is Tailwind CSS
// compiled from src/input.css to dist/tailwind.css (`npm run build:css` in
// this directory) — rebuild that before `go build` if src/input.css or
// index.html's class usage changes.
package webui

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed dist
var distFS embed.FS

// Handler serves the web companion's static assets rooted at "/". The
// embed.FS gives every file a zero mtime, so http.FileServer never emits
// Last-Modified/ETag — with no cache validator, browsers fall back to
// heuristic caching and can serve a stale copy after a redeploy. Explicit
// no-store avoids that during active development of dist/index.html.
func Handler() http.Handler {
	sub, err := fs.Sub(distFS, "dist")
	if err != nil {
		panic(err) // dist/ is embedded at build time — this can't fail at runtime
	}
	fileServer := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		// Defense-in-depth for the companion (PR-13). The bundle is fully
		// self-hosted (no CDN, no external fetch), so a strict CSP plus
		// framing/sniff/referrer controls blunt token theft if a path or
		// filename ever reaches an HTML sink. Inline script/style are the
		// bundle's own; nothing loads cross-origin.
		w.Header().Set("Content-Security-Policy",
			"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; object-src 'none'")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		fileServer.ServeHTTP(w, r)
	})
}
