// Package server — SSE (Server-Sent Events) handler.
package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

// SseEvent is a single server-sent event payload.
type SseEvent struct {
	Type   string `json:"type"`
	Path   string `json:"path,omitempty"`
	Action string `json:"action,omitempty"`
	ID     string `json:"id,omitempty"`
	Bytes  int64  `json:"bytes,omitempty"`
	Total  int64  `json:"total,omitempty"`
}

// EventHub broadcasts SseEvents to all connected SSE clients.
type EventHub struct {
	mu      sync.Mutex
	clients map[chan SseEvent]struct{}
}

// NewEventHub creates a new EventHub.
func NewEventHub() *EventHub {
	return &EventHub{clients: make(map[chan SseEvent]struct{})}
}

// Subscribe registers a new client channel with the hub.
func (h *EventHub) Subscribe() chan SseEvent {
	ch := make(chan SseEvent, 16)
	h.mu.Lock()
	h.clients[ch] = struct{}{}
	h.mu.Unlock()
	return ch
}

// Unsubscribe removes a client channel and closes it.
func (h *EventHub) Unsubscribe(ch chan SseEvent) {
	h.mu.Lock()
	delete(h.clients, ch)
	h.mu.Unlock()
	close(ch)
}

// Broadcast sends an event to all connected clients (non-blocking).
func (h *EventHub) Broadcast(e SseEvent) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.clients {
		select {
		case ch <- e:
		default:
			// Drop event for slow clients.
		}
	}
}

func sseHandler(hub *EventHub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			writeError(w, http.StatusInternalServerError, "INTERNAL", "streaming not supported")
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.WriteHeader(http.StatusOK)
		flusher.Flush()

		ch := hub.Subscribe()
		defer hub.Unsubscribe(ch)

		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()

		ctx := r.Context()
		for {
			select {
			case <-ctx.Done():
				return
			case evt := <-ch:
				data, err := json.Marshal(evt)
				if err != nil {
					continue
				}
				fmt.Fprintf(w, "data: %s\n\n", data)
				flusher.Flush()
			case <-ticker.C:
				fmt.Fprint(w, ": keepalive\n\n")
				flusher.Flush()
			}
		}
	}
}
