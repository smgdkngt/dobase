package cli

import (
	"bytes"
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
	want := `{"card":{"assigned_user_id":5,"color":"red","description":"<p>One &lt;b&gt;</p><p>Two</p>","due_date":"2026-10-01","title":"Ship it"}}`
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
	if got := sent[1].JSON(); got != `{"card":{"assigned_user_id":null,"color":"","due_date":null,"title":"Plan"}}` {
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
	if got := sent[0].JSON() + " " + sent[1].JSON(); got != `{"column_id":31} {"position":2}` {
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
	if got := sent[0].JSON(); got != `{"item":{"assigned_user_id":5,"recurrence_rule":"monthly","title":"Mow"}}` {
		t.Errorf("sent %s", got)
	}
	if got := sent[1].JSON(); got != `{"item":{"due_date":null,"recurrence_rule":null,"title":"Water"}}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), `Created todo 14/400 "" in Garden: `) || !strings.Contains(out.String(), `Updated todo 14/400 "".`) {
		t.Errorf("out %q", out.String())
	}
	if err := invoke(ctx, "todo update", "14/7", "--repeat", "yearly"); err == nil || err.Error() != "--repeat must be one of: daily, weekly, monthly, none" {
		t.Errorf("got %v", err)
	}
}
