package tui

// A todos tool: every list with its todos, ticked off with the spacebar.

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var todosHints = []hint{{"↑↓", "choose"}, {"space", "done"}, {"enter", "open"}, {"c", "new"}, {"e d", "rename, due"}, {"esc", "home"}}

var todosHelp = []hint{
	{"↑ ↓ / j k", "Choose a todo"},
	{"space / x", "Tick it off, or reopen it"},
	{"enter", "Open it: description and comments"},
	{"c", "New todo at the bottom of this list"},
	{"N", "New list"},
	{"e", "Rename it"},
	{"d", "Set its due date: fri, +3, tomorrow, 2026-10-01 or none"},
	{"i", "Assign it to yourself, or unassign"},
	{"o", "Open it in your browser"},
	{"u", "Undo the last change"},
	{"r", "Reload"},
	{"esc", "Back home"},
}

// todoRow is a list heading (item -1) or a todo in a list.
type todoRow struct{ list, item int }

type Todos struct {
	tool     api.Value
	lists    []api.Value
	rows     []todoRow
	selected int
}

func loadTodos(app *App, tool api.Value) (*Todos, error) {
	todo, err := app.get(toolPath(tool) + "/todo")
	if err != nil {
		return nil, err
	}
	screen := &Todos{tool: tool, lists: slices.Clone(todo.Get("lists").Items())}
	screen.index()
	if first := slices.IndexFunc(screen.rows, func(row todoRow) bool { return row.item >= 0 }); first >= 0 {
		screen.selected = first
	}
	return screen, nil
}

func itemsOf(list api.Value) []api.Value { return list.Get("items").Items() }

func (s *Todos) index() {
	s.rows = s.rows[:0]
	for list, value := range s.lists {
		s.rows = append(s.rows, todoRow{list, -1})
		for item := range itemsOf(value) {
			s.rows = append(s.rows, todoRow{list, item})
		}
	}
}

func (s *Todos) Tool() (api.Value, bool) { return s.tool, true }
func (s *Todos) Hints() []hint           { return todosHints }
func (s *Todos) Help() []hint            { return todosHelp }
func (s *Todos) toolID() int64           { return s.tool.Get("id").Int() }

func (s *Todos) LiveRequest() (string, []api.Param, bool) {
	return toolPath(s.tool) + "/todo", nil, true
}

func (s *Todos) ApplyLive(value api.Value) {
	s.replace(slices.Clone(value.Get("lists").Items()), 0)
}

func (s *Todos) item() (api.Value, bool) {
	if s.selected >= len(s.rows) || s.rows[s.selected].item < 0 {
		return api.Null, false
	}
	row := s.rows[s.selected]
	items := itemsOf(s.lists[row.list])
	if row.item >= len(items) {
		return api.Null, false
	}
	return items[row.item], true
}

func (s *Todos) list() (api.Value, bool) {
	if s.selected >= len(s.rows) {
		return api.Null, false
	}
	return s.lists[s.rows[s.selected].list], true
}

func (s *Todos) selectItem(id int64) {
	position := slices.IndexFunc(s.rows, func(row todoRow) bool {
		return row.item >= 0 && itemsOf(s.lists[row.list])[row.item].Get("id").Int() == id
	})
	if position >= 0 {
		s.selected = position
	}
}

func (s *Todos) Refresh() Job {
	return func(app *App) error { return reloadTodos(app, 0) }
}

// replace takes in fresh lists, keeping the selection on the same todo (or on selectID, when not 0).
func (s *Todos) replace(lists []api.Value, selectID int64) {
	if selectID == 0 {
		if item, ok := s.item(); ok {
			selectID = item.Get("id").Int()
		}
	}
	s.lists = lists
	s.index()
	s.selected = min(s.selected, sat(len(s.rows)-1))
	if selectID != 0 {
		s.selectItem(selectID)
	}
}

func (s *Todos) Key(key Key, view *View, fx *Fx) bool {
	switch {
	case key.Is(' ', 'x'):
		s.toggle(fx)
	case key.Code == KeyEnter:
		if item, ok := s.item(); ok {
			tool, id := s.toolID(), item.Get("id").Int()
			fx.job("Opening the todo", func(app *App) error {
				detail, err := todoDetail(app, tool, id)
				if err != nil {
					return err
				}
				app.popup = detail
				return nil
			})
		}
	case key.Is('c'):
		list, ok := s.list()
		if !ok {
			return true
		}
		listID, name := list.Get("id").S(), list.Get("title").S()
		fx.popup = inputPopup("New todo in "+name, "What needs doing?", "Adding the todo", func(app *App, title string) error {
			item, err := app.post("/todo_lists/"+listID+"/items", api.Object("item", api.Object("title", title)))
			if err != nil {
				return err
			}
			if err := reloadTodos(app, item.Get("id").Int()); err != nil {
				return err
			}
			app.say("Added “"+item.Get("title").S()+"” 📝", ToneSuccess)
			return nil
		})
	case key.Is('N'):
		tool := s.toolID()
		fx.popup = inputPopup("New list", "What's the list called?", "Adding the list", func(app *App, title string) error {
			if _, err := app.post(fmt.Sprintf("/tools/%d/todo/lists", tool), api.Object("title", title)); err != nil {
				return err
			}
			if err := reloadTodos(app, 0); err != nil {
				return err
			}
			app.say("Made the list “"+title+"”", ToneSuccess)
			return nil
		})
	case key.Is('i'):
		if item, ok := s.item(); ok {
			tool, id, assignee := s.toolID(), item.Get("id").Int(), item.Get("assignee", "id")
			fx.job("Assigning", func(app *App) error {
				mine := assignee.Equal(app.me.Get("id"))
				value := app.me.Get("id")
				if mine {
					value = api.Null
				}
				if err := updateItem(app, tool, id, api.Object("assigned_user_id", value)); err != nil {
					return err
				}
				if mine {
					app.say("Unassigned", ToneSuccess)
				} else {
					app.say("It's yours now 👍", ToneSuccess)
				}
				app.offerUndo("the assignment", func(app *App) error {
					return updateItem(app, tool, id, api.Object("assigned_user_id", assignee))
				})
				return nil
			})
		}
	case key.Is('e'):
		if item, ok := s.item(); ok {
			tool, id, old := s.toolID(), item.Get("id").Int(), item.Get("title").S()
			fx.popup = inputPopup("Rename the todo", "A new title", "Renaming", func(app *App, title string) error {
				if err := updateItem(app, tool, id, api.Object("title", title)); err != nil {
					return err
				}
				app.offerUndo("the rename", func(app *App) error { return updateItem(app, tool, id, api.Object("title", old)) })
				return nil
			}).prefilled(item.Get("title").S())
		}
	case key.Is('d'):
		if item, ok := s.item(); ok {
			tool, id, old := s.toolID(), item.Get("id").Int(), item.Get("due_date")
			fx.popup = inputPopup("Due date", "fri, +3, tomorrow, 2026-10-01 or none", "Setting the due date", func(app *App, text string) error {
				due, err := dueDate(text)
				if err != nil {
					return err
				}
				if err := updateItem(app, tool, id, api.Object("due_date", dueValue(due))); err != nil {
					return err
				}
				app.say(dueToast(due), ToneSuccess)
				app.offerUndo("the due date", func(app *App) error { return updateItem(app, tool, id, api.Object("due_date", old)) })
				return nil
			}).prefilled(item.Get("due_date").S())
		}
	case key.Is('o'):
		item, ok := s.item()
		if !ok {
			return false
		}
		fx.openURL = ptr(fmt.Sprintf("/tools/%d/todo?item=%s", s.toolID(), item.Get("id").S()))
	default:
		return moveSelection(&s.selected, len(s.rows), key)
	}
	return true
}

// toggle ticks the selected todo off (or reopens it) right away on screen.
func (s *Todos) toggle(fx *Fx) {
	if s.selected >= len(s.rows) || s.rows[s.selected].item < 0 {
		return
	}
	row := s.rows[s.selected]
	tool := s.toolID()
	items := slices.Clone(itemsOf(s.lists[row.list]))
	done := !items[row.item].Get("completed").Truthy()
	items[row.item] = items[row.item].With("completed", done)
	s.lists[row.list] = s.lists[row.list].With("items", items)
	id := items[row.item].Get("id").Int()
	if done {
		fx.confetti = true
	}
	label := "Reopening"
	if done {
		label = "Ticking it off"
	}
	path := fmt.Sprintf("/tools/%d/todo/items/%d/completion", tool, id)
	complete := func(app *App, done bool) (api.Value, error) {
		if done {
			return app.post(path, api.Object())
		}
		return app.delete(path)
	}
	fx.job(label, func(app *App) error {
		item, err := complete(app, done)
		if err != nil {
			return err
		}
		if err := reloadTodos(app, id); err != nil {
			return err
		}
		if done && item.Get("recurrence_rule").Truthy() {
			// Its next one is already on the list, so there's nothing simple to undo.
			app.say("Done! It's back "+item.Get("recurrence_rule").S()+" 🔁", ToneSuccess)
			return nil
		}
		undoLabel := "the reopening"
		if done {
			undoLabel = "the tick"
		}
		app.offerUndo(undoLabel, func(app *App) error {
			if _, err := complete(app, !done); err != nil {
				return err
			}
			return reloadTodos(app, id)
		})
		return nil
	})
}

func (s *Todos) Draw(b *Buffer, area Rect, view *View) {
	block := panel(toolIcon("todos")+" "+s.tool.Get("name").S(), true)
	if len(s.lists) == 0 {
		Paragraph{Lines: []Line{RawLine("No lists yet. Press N to make one.")}, Style: dim(), Block: block}.Render(b, area)
		return
	}
	width := sat(area.W - 8)
	items := make([]ListItem, len(s.rows))
	for i, row := range s.rows {
		if row.item >= 0 {
			items[i] = itemLine(itemsOf(s.lists[row.list])[row.item], width)
			continue
		}
		open := 0
		for _, item := range itemsOf(s.lists[row.list]) {
			if !item.Get("completed").Truthy() {
				open++
			}
		}
		spacer := RawLine(" ")
		if row.list == 0 {
			spacer = RawLine("")
		}
		items[i] = Item(spacer, LineOf(
			Styled(s.lists[row.list].Get("title").S(), Style{}.Fg(accent()).With(Bold)),
			Styled(fmt.Sprintf("  %d open", open), dim())))
	}
	List{Items: items, Block: block, Highlight: selected(), Symbol: "▸"}.Render(b, area, s.selected)
}

func itemLine(item api.Value, width int) ListItem {
	done := item.Get("completed").Truthy()
	check, titleStyle := Raw(" ☐ "), Style{}
	if done {
		check, titleStyle = Styled(" ✔ ", Style{}.Fg(success()).With(Bold)), dim().With(CrossedOut)
	}
	spans := []Span{check, Styled(truncate(item.Get("title").S(), sat(width-24)), titleStyle)}

	if due := item.Get("due_date"); !due.IsNull() && !done {
		style := dim()
		if due.S() < command.Today().Format(command.DateLayout) {
			style = Style{}.Fg(danger())
		}
		spans = append(spans, Styled("  📅 "+shortDate(due.S()), style))
	}
	if name := item.Get("assignee", "name"); !name.IsNull() {
		first := ""
		if fields := strings.Fields(name.S()); len(fields) > 0 {
			first = fields[0]
		}
		spans = append(spans, Styled("  @"+first, Style{}.Fg(personColor(name.S()))))
	}
	if item.Get("recurrence_rule").Truthy() {
		spans = append(spans, Styled("  🔁", dim()))
	}
	if count := item.Get("comments_count").Int(); count > 0 {
		spans = append(spans, Styled(fmt.Sprintf("  💬%d", count), dim()))
	}
	return Item(LineOf(spans...))
}

// reloadTodos reloads the todos on screen, selecting item when it's not 0.
func reloadTodos(app *App, item int64) error {
	screen, ok := app.screen.(*Todos)
	if !ok {
		return nil
	}
	fresh, err := app.get(toolPath(screen.tool) + "/todo")
	if err != nil {
		return err
	}
	if screen, ok := app.screen.(*Todos); ok {
		screen.replace(slices.Clone(fresh.Get("lists").Items()), item)
	}
	return nil
}

func updateItem(app *App, tool, id int64, attributes api.Value) error {
	if _, err := app.patch(fmt.Sprintf("/tools/%d/todo/items/%d", tool, id), api.Object("item", attributes)); err != nil {
		return err
	}
	return reloadTodos(app, id)
}

func todoDetail(app *App, tool, id int64) (*Detail, error) {
	item, err := app.get(fmt.Sprintf("/tools/%d/todo/items/%d", tool, id))
	if err != nil {
		return nil, err
	}
	var lines []Line
	field(&lines, "List", item.Get("list", "title").S())
	status := "open"
	if item.Get("completed").Truthy() {
		status = "done " + ago(item.Get("completed_at"))
	}
	field(&lines, "Status", status)
	field(&lines, "Assignee", item.Get("assignee", "name").S())
	if due := item.Get("due_date"); !due.IsNull() {
		field(&lines, "Due", shortDate(due.S()))
	}
	field(&lines, "Repeats", item.Get("recurrence_rule").S())
	field(&lines, "Created", ago(item.Get("created_at"))+" by "+item.Get("creator", "name").S())

	if description := item.Get("description").S(); strings.TrimSpace(description) != "" {
		heading(&lines, "Description")
		addText(&lines, description, 0)
	}
	comments(&lines, item)
	attachmentLines(&lines, item)

	var url *string
	if value := item.Get("url"); !value.IsNull() {
		url = ptr(value.S())
	}
	return &Detail{
		title: item.Get("title").S(),
		lines: lines,
		url:   url,
		comment: &CommentOn{
			path:   fmt.Sprintf("/tools/%d/todo/items/%d/comments", tool, id),
			reload: func(app *App) (*Detail, error) { return todoDetail(app, tool, id) },
		},
	}, nil
}
