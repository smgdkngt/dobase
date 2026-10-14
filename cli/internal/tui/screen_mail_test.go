package tui

import (
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// lastFolder is the folder the last mailbox was asked for.
func (h *harness) lastFolder() string {
	for i := len(*h.calls) - 1; i >= 0; i-- {
		if c := (*h.calls)[i]; c.path == "/tools/13/mails" {
			return c.query
		}
	}
	return ""
}

func TestFGoesThroughJunkOnlyWhenTheAccountHasIt(t *testing.T) {
	for _, test := range []struct {
		folders string
		after5  string
	}{
		{`["inbox", "drafts", "starred", "sent", "archive", "junk", "trash"]`, "folder=junk"},
		{`["inbox", "drafts", "starred", "sent", "archive", "trash"]`, "folder=inbox"},
	} {
		h := newHarness(t).answer("/tools/13/mails", `{ "folders": `+test.folders+`, "account": { "email_address": "sem@example.com" }, "conversations": [] }`)
		mail, err := loadMail(h.app, api.MustParse(`{ "id": 13, "name": "Mail", "type": "mail" }`), "inbox")
		if err != nil {
			t.Fatal(err)
		}
		h.app.screen = mail
		for range 5 {
			h.char('f')
		}
		if got := h.lastFolder(); got != test.after5 {
			t.Errorf("with %s, five folders on is %q, want %q", test.folders, got, test.after5)
		}
		if test.after5 == "folder=junk" {
			expectContains(t, h.text(), "junk")
		}
	}
}
