package main

import (
	"log"

	"github.com/zqamhieh/remote-file-explorer/agent/internal/server"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// pairPromptHandler announces an approve-on-PC pairing request to whoever is at
// the computer. The request stays answerable through `rfe-agent pair accept`
// and admin sessions whether or not a desktop notification could be shown.
func pairPromptHandler(db *store.DB) func(server.PairPrompt) {
	return func(p server.PairPrompt) {
		log.Printf("pair request from %q (%s), match code %s — `rfe-agent pair accept %s` or `pair reject %s`", p.Label, p.IP, p.SAS, p.ID[:8], p.ID[:8])
		go notifyPairPrompt(db, p)
	}
}
