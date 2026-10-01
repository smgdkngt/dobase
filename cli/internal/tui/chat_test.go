package tui

import (
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// requests counts the requests sent with this method to path.
func (h *harness) requests(method api.Method, path string) int {
	count := 0
	for _, c := range *h.calls {
		if c.method == method && c.path == path {
			count++
		}
	}
	return count
}

const oneMessage = `{ "id": 1, "user": { "id": 2, "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z", "reactions": [] }`

func TestOlderMessagesCanBeAskedForAgainAfterTheServerFailed(t *testing.T) {
	h := newHarness(t)
	h.answer("/tools/12/chat", `{ "messages": [`+oneMessage+`], "has_more": true }`)
	h.char('3')
	loads := h.requests(api.Get, "/tools/12/chat")

	h.fail("/tools/12/chat", true).code(KeyUp)
	expectContains(t, h.text(), "The server is having a moment")
	if got := h.requests(api.Get, "/tools/12/chat"); got != loads+1 {
		t.Fatalf("%d requests for older messages", got-loads)
	}

	h.fail("/tools/12/chat", false).code(KeyUp)
	if got := h.requests(api.Get, "/tools/12/chat"); got != loads+2 {
		t.Fatalf("scrolling up again asked for older messages %d times, want 2", got-loads)
	}
}

func TestTheLastMessageLeavesTheScreenWhenItIsDeleted(t *testing.T) {
	h := newHarness(t)
	h.char('3')
	expectContains(t, h.text(), "Morning!")

	h.answer("/tools/12/chat", `{ "messages": [], "has_more": false }`).char('r')
	if screen := h.text(); strings.Contains(screen, "Morning!") {
		t.Fatalf("the deleted message is still there:\n%s", screen)
	}
	expectContains(t, h.text(), "It's quiet in here.")
}

func TestAMessageThatCouldNotBeSentStaysInTheField(t *testing.T) {
	h := newHarness(t)
	h.fail("Post /tools/12/chat/messages", true)
	h.char('3').char('i').typing("Lunch at one?").code(KeyEnter)

	chat := h.app.screen.(*Chat)
	if got := chat.input.Text(); got != "Lunch at one?" || !chat.writing {
		t.Fatalf("the field holds %q", got)
	}
	expectContains(t, h.text(), "The server is having a moment", "Lunch at one?")

	h.fail("Post /tools/12/chat/messages", false).code(KeyEnter)
	if got := chat.input.Text(); got != "" {
		t.Fatalf("after sending, the field holds %q", got)
	}
}
