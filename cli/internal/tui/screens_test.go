package tui

import (
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// otherTools swaps the workspace for one with a docs and a files tool.
func otherTools(h *harness) *harness {
	h.answer("/tools", `[{ "id": 20, "name": "Shared", "type": "files" }, { "id": 21, "name": "Notes", "type": "docs" }]`)
	h.answer("/tools/21/docs", `{ "documents": [{ "id": 9, "title": "Plan", "updated_at": "2026-09-24T10:00:00Z" }] }`)
	h.answer("/tools/21/docs/documents/9", `{ "id": 9, "title": "Plan", "content": "First line\nSecond line",
		"updated_at": "2026-09-24T10:00:00Z", "updated_by": { "name": "Ann" } }`)
	h.answer("/tools/20/files", `{ "folder": { "id": 7, "name": "Contracts", "parent_id": null }, "breadcrumbs": [],
		"folders": [{ "id": 8, "name": "Old" }],
		"files": [{ "id": 30, "name": "draft.pdf", "file_size": 10, "created_at": "2026-09-24T10:00:00Z" },
		          { "id": 31, "name": "contract.pdf", "content_type": "application/pdf", "file_size": 2048, "created_at": "2026-09-24T10:00:00Z" }] }`)
	h.answer("/tools/20/files/items/31", `{ "id": 31, "name": "contract.pdf", "folder_id": 7, "file_size": 2048 }`)
	return h.char('r')
}

func TestADocumentDoesNotScrollPastItsEnd(t *testing.T) {
	h := otherTools(newHarness(t))
	h.char('1').code(KeyEnter)
	expectContains(t, h.text(), "First line")

	for range 40 {
		h.code(KeyDown)
	}
	h.char(' ')
	expectContains(t, h.text(), "First line", "Second line")
	h.code(KeyUp)
	expectContains(t, h.text(), "First line")
}

func TestAFileFoundBySearchOpensInItsFolder(t *testing.T) {
	h := otherTools(newHarness(t))
	h.answer("/search", `{ "results": [{ "kind": "file", "title": "contract.pdf", "tool_name": "Shared", "url": "http://localhost/tools/20/files/items/31" }] }`)
	h.char('/').typing("contract").code(KeyEnter).code(KeyEnter)

	var listing call
	for _, c := range *h.calls {
		if c.method == api.Get && c.path == "/tools/20/files" {
			listing = c
		}
	}
	if listing.query != "folder_id=7" {
		t.Fatalf("the files were asked for with %q:\n%s", listing.query, h.text())
	}
	expectContains(t, h.text(), "Shared / Contracts")

	// The file itself is selected
	h.code(KeyEnter)
	expectContains(t, h.text(), "application/pdf")
}

func TestANarrowWindowKeepsTheToolNameAndTheHelpKey(t *testing.T) {
	h := newHarness(t)
	h.answer("/tools", `[{ "id": 10, "name": "Product Launch Roadmap 2026", "type": "boards" }]`)
	h.char('r').char('1')
	h.screen.SetSize(54, 30)

	rows := strings.Split(h.text(), "\n")
	if header := rows[0]; !strings.Contains(header, "Product Launch Roadmap 2026") {
		t.Errorf("the header is %q", header)
	}
	if footer := rows[len(rows)-1]; !strings.Contains(footer, "? help") || !strings.Contains(footer, "enter open") {
		t.Errorf("the footer is %q", footer)
	}

	// With room for it, who and where is back
	h.screen.SetSize(80, 30)
	if header, _, _ := strings.Cut(h.text(), "\n"); !strings.Contains(header, "Sem Goedknegt · localhost") {
		t.Errorf("the wide header is %q", header)
	}
	h.screen.SetSize(62, 30)
	if header, _, _ := strings.Cut(h.text(), "\n"); !strings.Contains(header, "Roadmap 2026") || !strings.Contains(header, "Sem Goedknegt") || strings.Contains(header, "localhost") {
		t.Errorf("the header at 62 columns is %q", header)
	}
}
