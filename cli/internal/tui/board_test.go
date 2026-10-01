package tui

import "testing"

func TestMovingACardOnABoardWithoutColumnsDoesNothing(t *testing.T) {
	h := newHarness(t)
	h.answer("/tools/10/board", `{ "columns": [] }`)
	h.char('2')
	for _, key := range "JKHLjkhl" {
		h.char(key)
	}
	h.code(KeyEnter)
	expectContains(t, h.text(), "This board has no columns yet.")
}
