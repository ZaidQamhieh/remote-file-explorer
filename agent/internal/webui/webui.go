// Package webui serves the browser-based web companion (agent control,
// status, settings) as a static bundle embedded in the agent binary — one
// binary, one port, no separate hosting step. Vanilla JS/HTML, no build
// tool for markup: dist/index.html is served as-is. Styling is Tailwind CSS
// compiled from src/input.css to dist/tailwind.css (`npm run build:css` in
// this directory) — rebuild that before `go build` if src/input.css or
// index.html's class usage changes.
package webui

import (
	"crypto/rand"
	"embed"
	"encoding/base64"
	"io/fs"
	"net/http"
	"strings"
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
	index, err := fs.ReadFile(sub, "index.html")
	if err != nil {
		panic(err)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nonceBytes := make([]byte, 18)
		if _, err := rand.Read(nonceBytes); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'nonce-"+nonce+"'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			body := strings.Replace(string(index), "<script>", `<script nonce="`+nonce+`">`, 1)
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Content-Length", "")
			if r.Method != http.MethodHead {
				_, _ = w.Write([]byte(body))
			}
			return
		}
		fileServer.ServeHTTP(w, r)
	})
}
