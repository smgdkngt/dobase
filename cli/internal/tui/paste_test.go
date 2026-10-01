package tui

import (
	"testing"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/smgdkngt/dobase/cli/internal/api"
)

// pasteScreen notes whether the app asked the terminal to mark pasted text.
type pasteScreen struct {
	tcell.SimulationScreen
	marksPastes bool
}

func (s *pasteScreen) EnablePaste() {
	s.marksPastes = true
	s.SimulationScreen.EnablePaste()
}

// paste runs the app's loop on text pasted the way a terminal sends it: key
// presses between a start and an end. Ctrl-c ends the loop.
func (h *harness) paste(text string) *pasteScreen {
	screen := &pasteScreen{SimulationScreen: h.screen}
	events := []tcell.Event{tcell.NewEventPaste(true)}
	for _, char := range text {
		events = append(events, tcell.NewEventKey(tcell.KeyRune, char, tcell.ModNone))
	}
	events = append(events, tcell.NewEventPaste(false), tcell.NewEventKey(tcell.KeyCtrlC, 0, tcell.ModCtrl))
	go func() {
		for _, event := range events {
			// The queue is short: wait for the loop to make room.
			for screen.PostEvent(event) != nil {
				time.Sleep(time.Millisecond)
			}
		}
	}()
	loop(screen, h.app)
	h.app.quit = false
	return screen
}

func TestPastedLinesBecomeOneMessageToSend(t *testing.T) {
	h := newHarness(t)
	h.char('3').char('i')
	screen := h.paste("one\r\ntwo\n3")

	if !screen.marksPastes {
		t.Fatal("the terminal wasn't asked to mark pasted text")
	}
	if _, ok := h.sent(api.Post, "/tools/12/chat/messages"); ok {
		t.Fatal("a pasted line was sent as a message")
	}
	chat := h.app.screen.(*Chat)
	if got := chat.input.Text(); got != "one two 3" {
		t.Fatalf("the message is %q", got)
	}

	h.code(KeyEnter)
	h.expectSent(api.Post, "/tools/12/chat/messages", `{ "message": { "body": "<p>one two 3</p>" } }`)
}

func TestPastedTextGoesIntoAPopupsField(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('c')
	h.paste("Ship\tit")

	if _, ok := h.sent(api.Post, "/columns/1/cards"); ok {
		t.Fatal("the pasted text was saved before enter")
	}
	h.code(KeyEnter)
	h.expectSent(api.Post, "/columns/1/cards", `{ "card": { "title": "Ship it" } }`)
}

func TestPastedTextIsNotRunAsKeysWhenNothingIsBeingWritten(t *testing.T) {
	h := newHarness(t)
	h.paste("2\nLq")

	if _, home := h.app.screen.(*Home); !home || h.app.popup != nil {
		t.Fatalf("the pasted text opened something:\n%s", h.text())
	}
	if _, ok := h.sent(api.Patch, "/tools/10/board/cards/101/position"); ok {
		t.Fatal("the pasted text moved a card")
	}
}
