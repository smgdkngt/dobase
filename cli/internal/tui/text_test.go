package tui

import (
	"strings"
	"testing"
)

func TestWideTextWrapsByTheCellsItTakes(t *testing.T) {
	text := strings.Repeat("日本語", 20) + " 👍👍👍👍👍👍👍👍👍👍👍👍 end"
	lines := wrap(text, 30)
	for _, line := range lines {
		if width := textWidth(line); width > 30 {
			t.Errorf("%q takes %d cells", line, width)
		}
	}
	if got := strings.ReplaceAll(strings.Join(lines, ""), " ", ""); got != strings.ReplaceAll(text, " ", "") {
		t.Errorf("wrapping lost text: %q", got)
	}
}

func TestALongMessageInWideCharactersShowsToItsEnd(t *testing.T) {
	h := newHarness(t)
	h.answer("/tools/12/chat", `{ "messages": [{ "id": 1, "user": { "name": "Ann" }, "body": "`+strings.Repeat("日本語", 30)+`おわり",
		"created_at": "2026-09-24T08:00:00Z", "reactions": [] }] }`)
	h.char('3')
	expectContains(t, h.text(), "おわり")
}

func TestATextFieldKeepsTheCursorInSightInWideText(t *testing.T) {
	input := textInputWith(strings.Repeat("日", 20) + "本")
	b := NewBuffer(10, 1)
	input.Render(b, b.Area, "", true)

	// Four characters of two cells each fit before the cursor.
	if b.cursor == nil || b.cursor[0] != 8 {
		t.Fatalf("the cursor is at %v", b.cursor)
	}
	if last := b.at(6, 0).symbol; last != "本" {
		t.Fatalf("the character before the cursor is %q", last)
	}
}

func TestFilesWithWideNamesKeepTheirColumns(t *testing.T) {
	h := newHarness(t)
	h.answer("/tools", `[{ "id": 20, "name": "Shared", "type": "files" }]`)
	h.answer("/tools/20/files", `{ "folders": [], "files": [
		{ "id": 1, "name": "報告書.pdf", "file_size": 2048, "created_at": "2026-09-24T10:00:00Z" },
		{ "id": 2, "name": "report.pdf", "file_size": 2048, "created_at": "2026-09-24T10:00:00Z" }
	] }`)
	h.char('r').char('1')

	var columns []int
	for _, row := range strings.Split(h.text(), "\n") {
		if before, _, found := strings.Cut(row, "2.0 KB"); found {
			columns = append(columns, textWidth(before))
		}
	}
	if len(columns) != 2 || columns[0] != columns[1] {
		t.Fatalf("the sizes start at %v:\n%s", columns, h.text())
	}
}
