package tui

import (
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

func TestALongCardScrollsToItsLastLine(t *testing.T) {
	h := newHarness(t)
	// Long words wrap early, so the text takes more rows than its length divided by the width.
	description := strings.TrimSpace(strings.Repeat(strings.Repeat("x", 40)+" ", 80))
	h.answer("/tools/10/board/cards/101", `{ "id": 101, "title": "Fix login", "description": "`+description+`",
		"column": { "name": "To Do" }, "attachments": [],
		"comments": [{ "user": { "name": "Ann" }, "body": "The last line", "created_at": "2026-09-24T10:00:00Z" }] }`)
	h.char('2').code(KeyEnter)

	for range 200 {
		h.code(KeyDown)
	}
	expectContains(t, h.text(), "The last line")
}

func TestOnlyYConfirms(t *testing.T) {
	const archive = "/tools/10/board/cards/101/archive"
	h := newHarness(t)
	h.char('2').char('a')
	expectContains(t, h.text(), "y yes · any other key no")

	h.code(KeyEnter)
	if h.app.popup != nil || h.requests(api.Post, archive) != 0 {
		t.Fatalf("enter archived the card, or left the question open: %v", *h.calls)
	}

	h.char('a').char('y')
	if h.requests(api.Post, archive) != 1 {
		t.Fatal("y didn't archive the card")
	}
}
