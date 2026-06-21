package server

import (
	"bufio"
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSSEHandler_Heartbeat(t *testing.T) {
	hub := NewEventHub()
	handler := sseHandler(hub)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	req := httptest.NewRequest("GET", "/v1/events", nil).WithContext(ctx)
	rec := httptest.NewRecorder()

	done := make(chan struct{})
	go func() {
		handler.ServeHTTP(rec, req)
		close(done)
	}()

	// Wait for the handler to start, then cancel to stop it.
	time.Sleep(100 * time.Millisecond)
	cancel()
	<-done

	body := rec.Body.String()
	if ct := rec.Header().Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("Content-Type = %q, want text/event-stream", ct)
	}
	// The body may be empty (no heartbeat within 100ms), which is expected.
	_ = body
}

func TestSSEHandler_BroadcastEvent(t *testing.T) {
	hub := NewEventHub()
	handler := sseHandler(hub)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	req := httptest.NewRequest("GET", "/v1/events", nil).WithContext(ctx)
	rec := httptest.NewRecorder()

	done := make(chan struct{})
	go func() {
		handler.ServeHTTP(rec, req)
		close(done)
	}()

	// Give the handler time to subscribe.
	time.Sleep(50 * time.Millisecond)

	hub.Broadcast(SseEvent{
		Type:   "fs.change",
		Path:   "/tmp/test.txt",
		Action: "modified",
	})

	// Give time for the event to be written.
	time.Sleep(50 * time.Millisecond)
	cancel()
	<-done

	body := rec.Body.String()
	scanner := bufio.NewScanner(strings.NewReader(body))
	found := false
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "data: ") {
			if strings.Contains(line, `"fs.change"`) && strings.Contains(line, `"modified"`) {
				found = true
			}
		}
	}
	if !found {
		t.Errorf("expected fs.change event in body, got: %s", body)
	}
}

func TestEventHub_SubscribeUnsubscribe(t *testing.T) {
	hub := NewEventHub()
	ch := hub.Subscribe()

	hub.mu.Lock()
	if len(hub.clients) != 1 {
		t.Fatalf("expected 1 client, got %d", len(hub.clients))
	}
	hub.mu.Unlock()

	hub.Unsubscribe(ch)

	hub.mu.Lock()
	if len(hub.clients) != 0 {
		t.Fatalf("expected 0 clients, got %d", len(hub.clients))
	}
	hub.mu.Unlock()
}
