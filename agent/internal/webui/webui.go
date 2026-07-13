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

// Handler serves the web companion's static assets rooted at "/".
func Handler() http.Handler {
	sub, err := fs.Sub(distFS, "dist")
	if err != nil {
		panic(err) // dist/ is embedded at build time — this can't fail at runtime
	}
	return http.FileServer(http.FS(sub))
}
