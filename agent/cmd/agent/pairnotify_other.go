//go:build !linux

package main

import (
	"github.com/zqamhieh/remote-file-explorer/agent/internal/server"
	"github.com/zqamhieh/remote-file-explorer/agent/internal/store"
)

// notifyPairPrompt has no desktop notification on this platform; the request is
// answered with `rfe-agent pair accept|reject` or an admin session.
func notifyPairPrompt(*store.DB, server.PairPrompt) {}
