package cli

import (
	"bytes"
	"slices"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

const boardsAndTodos = `{
  "/tools": [{"id": 13, "name": "Roadmap", "type": "boards"}, {"id": 14, "name": "Chores", "type": "todos"}],
  "/tools/13": {"collaborators": [{"id": 5, "name": "Ann Smith", "email_address": "ann@example.com"}, {"id": 6, "name": "Bob", "email_address": "bob@example.com"}]},
  "/tools/13/board": {"columns": [{"id": 30, "name": "To do", "cards": []}, {"id": 31, "name": "Doing", "cards": []}]},
  "/tools/14": {"collaborators": [{"id": 5, "name": "Ann Smith", "email_address": "ann@example.com"}]},
  "/tools/14/todo": {"url": "https://dobase.test/tools/14/todo", "lists": [
    {"id": 40, "title": "Home", "items": [
      {"id": 7, "title": "Water plants", "completed": false, "due_date": "2026-10-01", "assignee": {"name": "Ann Smith"},
       "recurrence_rule": "weekly", "comments_count": 2, "attachments_count": 1},
      {"id": 8, "title": "Fix tap", "completed": true, "completed_at": "2026-09-20T10:00:00Z", "due_date": null, "assignee": null,
       "recurrence_rule": null, "comments_count": 0, "attachments_count": 0}
    ]},
    {"id": 41, "title": "Garden", "items": []}
  ]}
}`

func newBoardsCtx(sent *[]api.Value) (*command.Ctx, *bytes.Buffer) {
	var out bytes.Buffer
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(newFakeAPI(boardsAndTodos, sent))
	return ctx, &out
}

func TestCardCreateResolvesTheColumnAssigneeAndDueDate(t *testing.T) {
	var sent []api.Value
	ctx, out := newBoardsCtx(&sent)

	err := invoke(ctx, "card create", "roadmap", "Ship it", "--column", "doi", "--assignee", "ann", "--due", "2026-10-01",
		"--color", "red", "--description", "One <b>\n\nTwo")
	if err != nil {
		t.Fatal(err)
	}
	want := `{"assignee":"5","color":"red","column":"31","description":"<p>One &lt;b&gt;</p><p>Two</p>","due":"2026-10-01","html":true,"title":"Ship it","tool_id":13}`
	if got := sent[0].JSON(); got != want {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), "Created card 13/400 \"\" in Doing: https://dobase.test/tools/8/mails/new?draft_id=400") {
		t.Errorf("out %q", out.String())
	}

	// Without --column the card goes to the first column; none clears the date,
	// the assignee and the color.
	if err := invoke(ctx, "card create", "13", "Plan", "--due", "none", "--assignee", "none", "--color", "none"); err != nil {
		t.Fatal(err)
	}
	if got := sent[1].JSON(); got != `{"assignee":"none","color":"none","column":"30","due":"none","title":"Plan","tool_id":13}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), " in To do: ") {
		t.Errorf("out %q", out.String())
	}

	if err := invoke(ctx, "card create", "13", "Plan", "--column", "Done"); err == nil || err.Error() != `No column matches "Done". Columns: To do, Doing` {
		t.Errorf("got %v", err)
	}
	if err := invoke(ctx, "card create", "13", "Plan", "--color", "pink"); err == nil || api.KindOf(err) != api.Usage {
		t.Errorf("got %v", err)
	}
	if err := invoke(ctx, "card update", "13/9"); err == nil || err.Error() != "Nothing to update. See `dobase help card`." {
		t.Errorf("got %v", err)
	}
}

func TestCardMoveSendsOnlyWhatWasGiven(t *testing.T) {
	var sent []api.Value
	ctx, _ := newBoardsCtx(&sent)

	if err := invoke(ctx, "card move", "13/9", "doing"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "card move", "13/9", "--position", "3"); err != nil {
		t.Fatal(err)
	}
	if got := sent[0].JSON() + " " + sent[1].JSON(); got != `{"card_id":9,"column":"31","tool_id":13} {"card_id":9,"position":3,"tool_id":13}` {
		t.Errorf("sent %s", got)
	}
	if err := invoke(ctx, "card move", "13/9"); err == nil || err.Error() != "Give a COLUMN, a --position, or both." {
		t.Errorf("got %v", err)
	}
}

func TestTodoListShowsListsWithTheirTodos(t *testing.T) {
	var sent []api.Value
	ctx, out := newBoardsCtx(&sent)

	if err := invoke(ctx, "todo list", "chores"); err != nil {
		t.Fatal(err)
	}
	want := `Chores (todos 14) https://dobase.test/tools/14/todo

Home [list 40]
  14/7  [ ]  Water plants  due 2026-10-01  @Ann Smith  repeats weekly  2 comments  1 file
  14/8  [x]  Fix tap       done 2026-09-20

Garden [list 41]
  (no todos)
`
	if out.String() != want {
		t.Errorf("out %q", out.String())
	}
}

func TestTodoCreateAndUpdateBodies(t *testing.T) {
	var sent []api.Value
	ctx, out := newBoardsCtx(&sent)

	if err := invoke(ctx, "todo create", "chores", "Mow", "--list", "gar", "--repeat", "monthly", "--assignee", "ann@example.com"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "todo update", "14/7", "--repeat", "none", "--due", "none", "--title", "Water"); err != nil {
		t.Fatal(err)
	}
	if got := sent[0].JSON(); got != `{"assignee":"5","list":"41","repeat":"monthly","title":"Mow","tool_id":14}` {
		t.Errorf("sent %s", got)
	}
	if got := sent[1].JSON(); got != `{"due":"none","repeat":"none","title":"Water","todo_id":7,"tool_id":14}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), `Created todo 14/400 "" in Garden: `) || !strings.Contains(out.String(), `Updated todo 14/400 "".`) {
		t.Errorf("out %q", out.String())
	}
	if err := invoke(ctx, "todo update", "14/7", "--repeat", "yearly"); err == nil || err.Error() != "--repeat must be one of: daily, weekly, monthly, none" {
		t.Errorf("got %v", err)
	}
}

func TestCommentsAreDeletedByTheIDShowPrints(t *testing.T) {
	var sent []api.Value
	var out bytes.Buffer
	fake := newFakeAPI(boardsAndTodos, &sent)
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(fake)

	if err := invoke(ctx, "card uncomment", "roadmap/104", "77"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "todo uncomment", "14/7", "78"); err != nil {
		t.Fatal(err)
	}
	want := []string{"card_uncomment", "todo_uncomment"}
	if !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].JSON() + " " + sent[1].JSON(); got != `{"card_id":104,"comment_id":77,"confirm":true,"tool_id":13} {"comment_id":78,"confirm":true,"todo_id":7,"tool_id":14}` {
		t.Errorf("sent %s", got)
	}
	if want := "Deleted comment 77 from card 13/104.\nDeleted comment 78 from todo 14/7.\n"; out.String() != want {
		t.Errorf("out %q", out.String())
	}

	for _, comment := range []string{"first", "13/104", "-1"} {
		if err := invoke(ctx, "card uncomment", "13/104", comment); api.KindOf(err) != api.Usage || !strings.Contains(err.Error(), "comment id like 77") {
			t.Errorf("%s: %v", comment, err)
		}
	}
}
