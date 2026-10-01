package tui

import (
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

func TestUOnlyUndoesTheLastChange(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('L')
	expectContains(t, h.text(), "u undo")

	// A new card can't be undone, and the move before it is no longer the last change.
	h.char('c').typing("Ship it").code(KeyEnter)
	if screen := h.text(); strings.Contains(screen, "u undo") {
		t.Fatalf("undo is still offered:\n%s", screen)
	}
	h.char('u')
	expectContains(t, h.text(), "Nothing to undo")
	if moves := h.requests(api.Patch, "/tools/10/board/cards/101/position"); moves != 1 {
		t.Fatalf("u moved the card back: %d moves", moves)
	}
}

func TestLookingAroundKeepsTheUndo(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('L').code(KeyEnter).code(KeyEsc).char('r').char('n').code(KeyEsc)
	expectContains(t, h.text(), "u undo")

	h.char('u')
	h.expectSent(api.Patch, "/tools/10/board/cards/101/position", `{ "column_id": 1, "position": 0 }`)
}

func TestAThumbsUpThatWasAlreadyThereIsNotUndone(t *testing.T) {
	const reactions = "/tools/12/chat/messages/1/reactions"
	h := newHarness(t)
	h.answer("/tools/12/chat", `{ "messages": [{ "id": 1, "user": { "id": 2, "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z",
		"reactions": [{ "emoji": "🎉", "count": 1, "users": [{ "id": 1, "name": "Sem Goedknegt" }] },
		              { "emoji": "👍", "count": 2, "users": [{ "id": 2, "name": "Ann" }, { "id": 1, "name": "Sem Goedknegt" }] }] }] }`)
	h.char('3').char('+').char('u')

	expectContains(t, h.text(), "Nothing to undo")
	if removed := h.requests(api.Delete, reactions+"/%F0%9F%91%8D"); removed != 0 {
		t.Fatal("u took away a 👍 that was given earlier")
	}
}

func TestANewThumbsUpIsUndone(t *testing.T) {
	const reactions = "/tools/12/chat/messages/1/reactions"
	h := newHarness(t)
	h.answer("/tools/12/chat", `{ "messages": [{ "id": 1, "user": { "id": 2, "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z",
		"reactions": [{ "emoji": "👍", "count": 1, "users": [{ "id": 2, "name": "Ann" }] }] }] }`)
	h.char('3').char('+').char('u')

	h.expectSent(api.Post, reactions, `{ "emoji": "👍" }`)
	if removed := h.requests(api.Delete, reactions+"/%F0%9F%91%8D"); removed != 1 {
		t.Fatalf("u removed the 👍 %d times", removed)
	}
}
