package tui

import (
	"context"
	"slices"
	"testing"
	"time"
)

// fakeStream is a server's stream that tells of what is pushed into it.
type fakeStream struct {
	uris  chan []string
	tells chan string
	told  chan struct{}
}

func (f *fakeStream) Listen(ctx context.Context, uris []string, opened func(), changed func(uri string)) error {
	f.uris <- uris
	opened()
	for {
		select {
		case <-ctx.Done():
			return nil
		case uri := <-f.tells:
			changed(uri)
			f.told <- struct{}{}
		}
	}
}

// liveCalls counts the background's reloads of the board.
func boardReloads(h *harness) int {
	h.server.mu.Lock()
	defer h.server.mu.Unlock()
	n := 0
	for _, c := range *h.calls {
		if c.path == "/tools/10/board" {
			n++
		}
	}
	return n
}

// tick lets the background pick up what it heard and finish what it asked.
func tick(h *harness) {
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		h.app.pollBackground()
		if h.app.background.inflight == nil && len(h.app.background.heard) == 0 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestAChangeTheStreamTellsOfIsFetchedAtOnce(t *testing.T) {
	h := newHarness(t)
	h.app.refreshInBackground(h.server)
	stream := &fakeStream{uris: make(chan []string, 1), tells: make(chan string), told: make(chan struct{})}
	ctx, stop := context.WithCancel(context.Background())
	defer stop()
	h.app.listen(ctx, stream)

	uris := <-stream.uris
	if want := []string{"dobase://events", "dobase://tools/11", "dobase://tools/10", "dobase://tools/12"}; !slices.Equal(uris, want) {
		t.Fatalf("subscribed to %v", uris)
	}
	for !h.app.background.streaming.Load() {
		time.Sleep(time.Millisecond)
	}

	h.char('2') // the board
	if _, ok := h.app.screen.(*Board); !ok {
		t.Fatalf("not on the board:\n%s", h.text())
	}
	h.app.lastRefresh = time.Now()
	before := boardReloads(h)

	// A change to another tool, and nothing told: the board waits for the slow poll
	stream.tells <- "dobase://tools/11"
	<-stream.told
	tick(h)
	if boardReloads(h) != before {
		t.Fatalf("the board was fetched for another tool's change")
	}

	stream.tells <- "dobase://tools/10"
	<-stream.told
	tick(h)
	if boardReloads(h) != before+1 {
		t.Fatalf("the board wasn't fetched when its change was told: %d reloads", boardReloads(h)-before)
	}

	// While the stream is open the poll only comes every minute
	h.app.lastRefresh = time.Now().Add(-30 * time.Second)
	tick(h)
	if boardReloads(h) != before+1 {
		t.Fatalf("polled after half a minute while the stream was open")
	}
	h.app.background.streaming.Store(false)
	tick(h)
	if boardReloads(h) != before+2 {
		t.Fatalf("without the stream the poll didn't come after ten seconds")
	}
}
