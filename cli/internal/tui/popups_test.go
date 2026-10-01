package tui

import (
	"strings"
	"testing"
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
