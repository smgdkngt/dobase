package commands

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

var todoRepeats = []string{"daily", "weekly", "monthly"}

func todoFlags() []Flag {
	return []Flag{
		F("description", "TEXT", "Description (plain text, or HTML with --html)"),
		Switch("html", "The description is HTML"),
		F("due", "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none"),
		F("assignee", "USER", "me, none, a user id, email or name"),
		F("repeat", "RULE", strings.Join(todoRepeats, ", ")+" or none"),
	}
}

func todos() []*Definition {
	return []*Definition{
		New("todo list", "Show a todos tool: its lists with their open and recently completed todos", []string{"TOOL"},
			[]Flag{Switch("completed", "Show every completed todo instead")}, listTodos),
		New("todo show", "Show a todo with its description, comments and attachments", []string{"TOOL/ITEM"}, nil, showTodo),
		New("todo create", "Add a todo to the bottom of a list (the first list unless --list)", []string{"TOOL", "TITLE"},
			append(todoFlags(), F("list", "LIST", "List id or name")), createTodo),
		New("todo update", "Change a todo's title, description, due date, assignee or repeat", []string{"TOOL/ITEM"},
			append(todoFlags(), F("title", "TEXT", "New title")), updateTodo),
		New("todo finish", "Mark a todo as done (a repeating todo comes back with its next due date)", []string{"TOOL/ITEM"}, nil, finishTodo),
		New("todo reopen", "Mark a completed todo as not done", []string{"TOOL/ITEM"}, nil, reopenTodo),
		New("todo move", "Move a todo to another list, or to a position within its list", []string{"TOOL/ITEM", "[LIST]"},
			[]Flag{F("position", "N", "Position in the list, 1 = top (default: bottom)")}, moveTodo),
		New("todo delete", "Delete a todo permanently, with its comments and attachments", []string{"TOOL/ITEM"}, nil, deleteTodo),
		New("todo comment", "Comment on a todo", []string{"TOOL/ITEM", "TEXT"}, []Flag{Switch("html", "TEXT is HTML")}, commentTodo),
		New("todo uncomment", "Delete a comment from a todo: one of your own, or anyone's on a tool you own", []string{"TOOL/ITEM", "COMMENT"}, nil, uncommentTodo),
		New("todo attach", "Attach files to a todo (25 MB max each)", []string{"TOOL/ITEM", "PATH..."}, nil, attachTodo),
		New("todolist create", "Add a list to the end of a todos tool", []string{"TOOL", "TITLE"}, nil, createTodoList),
		New("todolist rename", "Rename a list", []string{"TOOL/LIST", "TITLE"}, nil, renameTodoList),
		New("todolist delete", "Delete a list and every todo on it", []string{"TOOL/LIST"}, nil, deleteTodoList),
	}
}

func listTodos(ctx *Ctx, args *Args) error {
	completed := args.On("completed")
	tool, err := ctx.Tool(args.At(0), "todos")
	if err != nil {
		return err
	}
	todo, err := ctx.Get(fmt.Sprintf("/tools/%s/todo", tool.Get("id").S()), "completed", If(completed, "true"))
	if err != nil {
		return err
	}

	return ctx.Output(todo, func() error {
		ctx.Sayf("%s (todos %s) %s", tool.Get("name").S(), tool.Get("id").S(), todo.Get("url").S())
		for _, list := range todo.Get("lists").Items() {
			ctx.Blank()
			ctx.Sayf("%s [list %s]", list.Get("title").S(), list.Get("id").S())
			items := list.Get("items").Items()
			if len(items) == 0 {
				ctx.Sayf("  (no %stodos)", If(completed, "completed "))
			}
			var rows [][]string
			for _, item := range items {
				check := "[ ]"
				if item.Get("completed").Truthy() {
					check = "[x]"
				}
				rows = append(rows, []string{tool.Get("id").S() + "/" + item.Get("id").S(), check, item.Get("title").S(), todoSummary(item)})
			}
			ctx.Table(rows, 2)
		}
		return nil
	})
}

func showTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	item, err := ctx.Get(fmt.Sprintf("/tools/%s/todo/items/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	return ctx.Output(item, func() error {
		ctx.Sayf("%s (todo %s/%s)", item.Get("title").S(), tool.Get("id").S(), item.Get("id").S())
		ctx.Field("List", tool.Get("name").S()+" › "+item.Get("list", "title").S())
		status := "open"
		if item.Get("completed").Truthy() {
			status = "done " + Moment(item.Get("completed_at"))
		}
		ctx.Field("Status", status)
		ctx.Field("Assignee", Person(item.Get("assignee")))
		ctx.Field("Due", item.Get("due_date").S())
		ctx.Field("Repeats", item.Get("recurrence_rule").S())
		ctx.Field("Created", Join(" by ", Moment(item.Get("created_at")), item.Get("creator", "name").S()))
		ctx.Field("URL", item.Get("url").S())
		showDetails(ctx, item)
		return nil
	})
}

func createTodo(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "todos")
	if err != nil {
		return err
	}
	target, err := findTodoList(ctx, tool, args.Value("list"))
	if err != nil {
		return err
	}

	attributes, err := todoAttributes(ctx, tool, args)
	if err != nil {
		return err
	}
	attributes["title"] = args.At(1)
	item, err := ctx.Post(fmt.Sprintf("/todo_lists/%s/items", target.Get("id").S()), map[string]any{"item": attributes})
	if err != nil {
		return err
	}
	return ctx.Output(item, func() error {
		ctx.Sayf("Created todo %s/%s %s in %s: %s", tool.Get("id").S(), item.Get("id").S(), Quoted(item.Get("title").S()),
			target.Get("title").S(), item.Get("url").S())
		return nil
	})
}

func updateTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	attributes, err := todoAttributes(ctx, tool, args)
	if err != nil {
		return err
	}
	if title, ok := args.Flag("title"); ok {
		attributes["title"] = title
	}
	if len(attributes) == 0 {
		return api.Usagef("Nothing to update. See `dobase help todo`.")
	}

	item, err := ctx.Patch(fmt.Sprintf("/tools/%s/todo/items/%d", tool.Get("id").S(), id), map[string]any{"item": attributes})
	if err != nil {
		return err
	}
	return ctx.Output(item, func() error {
		ctx.Sayf("Updated todo %s/%s %s.", tool.Get("id").S(), item.Get("id").S(), Quoted(item.Get("title").S()))
		return nil
	})
}

func finishTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	item, err := ctx.Post(fmt.Sprintf("/tools/%s/todo/items/%d/completion", tool.Get("id").S(), id), map[string]any{})
	if err != nil {
		return err
	}

	return ctx.Output(item, func() error {
		ctx.Sayf("Completed todo %s/%s %s.", tool.Get("id").S(), item.Get("id").S(), Quoted(item.Get("title").S()))
		if rule := item.Get("recurrence_rule"); !rule.IsNull() {
			ctx.Sayf("It repeats %s, so the next one is on the list.", rule.S())
		}
		return nil
	})
}

func reopenTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	item, err := ctx.Delete(fmt.Sprintf("/tools/%s/todo/items/%d/completion", tool.Get("id").S(), id))
	if err != nil {
		return err
	}
	return ctx.Output(item, func() error {
		ctx.Sayf("Reopened todo %s/%s %s.", tool.Get("id").S(), item.Get("id").S(), Quoted(item.Get("title").S()))
		return nil
	})
}

func moveTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	list, hasList := args.Get(1), len(args.Positional) > 1
	position, hasPosition := args.Flag("position")
	if !hasList && !hasPosition {
		return api.Usagef("Give a LIST, a --position, or both.")
	}

	body := map[string]any{}
	if hasList {
		target, err := findTodoList(ctx, tool, list)
		if err != nil {
			return err
		}
		body["todo_list_id"] = target.Get("id")
	}
	if hasPosition {
		body["position"] = zeroBased(position)
	}
	item, err := ctx.Patch(fmt.Sprintf("/tools/%s/todo/items/%d/position", tool.Get("id").S(), id), Compact(body))
	if err != nil {
		return err
	}
	return ctx.Output(item, func() error {
		ctx.Sayf("Moved todo %s/%s %s to %s, position %d.", tool.Get("id").S(), item.Get("id").S(), Quoted(item.Get("title").S()),
			item.Get("list", "title").S(), item.Get("position").Int()+1)
		return nil
	})
}

func deleteTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/todo/items/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted todo %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func commentTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	body, err := ctx.RichText(args.At(1), args.On("html"))
	if err != nil {
		return err
	}
	comment, err := ctx.Post(fmt.Sprintf("/tools/%s/todo/items/%d/comments", tool.Get("id").S(), id), map[string]any{"body": body})
	if err != nil {
		return err
	}
	return ctx.Output(comment, func() error {
		ctx.Sayf("Commented on todo %s/%d [comment %s].", tool.Get("id").S(), id, comment.Get("id").S())
		return nil
	})
}

func uncommentTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/todo/items/%d/comments", tool.Get("id").S(), id)
	return deleteComment(ctx, path, args.At(1), fmt.Sprintf("todo %s/%d", tool.Get("id").S(), id))
}

func attachTodo(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "item")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/todo/items/%d/attachments", tool.Get("id").S(), id)
	label := fmt.Sprintf("todo %s/%d", tool.Get("id").S(), id)
	return attachFiles(ctx, path, args.Rest(1), label)
}

func createTodoList(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "todos")
	if err != nil {
		return err
	}
	list, err := ctx.Post(fmt.Sprintf("/tools/%s/todo/lists", tool.Get("id").S()), map[string]any{"title": args.At(1)})
	if err != nil {
		return err
	}
	return ctx.Output(list, func() error {
		ctx.Sayf("Created list %s/%s %s.", tool.Get("id").S(), list.Get("id").S(), Quoted(list.Get("title").S()))
		return nil
	})
}

func renameTodoList(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "list")
	if err != nil {
		return err
	}
	list, err := ctx.Patch(fmt.Sprintf("/tools/%s/todo/lists/%d", tool.Get("id").S(), id), map[string]any{"title": args.At(1)})
	if err != nil {
		return err
	}
	return ctx.Output(list, func() error {
		ctx.Sayf("Renamed list %s/%s to %s.", tool.Get("id").S(), list.Get("id").S(), Quoted(list.Get("title").S()))
		return nil
	})
}

func deleteTodoList(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "todos", "list")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/todo/lists/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted list %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func todoSummary(item api.Value) string {
	return Join("  ",
		If(item.Get("completed").Truthy(), "done "+Day(item.Get("completed_at"))),
		If(!item.Get("due_date").IsNull(), "due "+item.Get("due_date").S()),
		If(item.Get("assignee").Truthy(), "@"+item.Get("assignee", "name").S()),
		If(!item.Get("recurrence_rule").IsNull(), "repeats "+item.Get("recurrence_rule").S()),
		If(item.Get("comments_count").Int() > 0, Count(item.Get("comments_count").Int(), "comment")),
		If(item.Get("attachments_count").Int() > 0, Count(item.Get("attachments_count").Int(), "file")),
	)
}

func findTodoList(ctx *Ctx, tool api.Value, reference string) (api.Value, error) {
	todo, err := ctx.Get(fmt.Sprintf("/tools/%s/todo", tool.Get("id").S()))
	if err != nil {
		return api.Null, err
	}
	return findNamed(todo.Get("lists").Items(), reference, "title", "list", "Lists", tool.Get("name").S())
}

func todoAttributes(ctx *Ctx, tool api.Value, args *Args) (map[string]any, error) {
	attributes := map[string]any{}
	if description, ok := args.Flag("description"); ok {
		text, err := ctx.RichText(description, args.On("html"))
		if err != nil {
			return nil, err
		}
		attributes["description"] = text
	}
	if due, ok := args.Flag("due"); ok {
		date, err := dueDateParam(due)
		if err != nil {
			return nil, err
		}
		attributes["due_date"] = date
	}
	if assignee, ok := args.Flag("assignee"); ok {
		user, err := ctx.UserID(tool, assignee)
		if err != nil {
			return nil, err
		}
		attributes["assigned_user_id"] = user
	}
	if repeat, ok := args.Flag("repeat"); ok {
		if !slices.Contains(todoRepeats, repeat) && repeat != "none" {
			return nil, api.Usagef("--repeat must be one of: %s, none", strings.Join(todoRepeats, ", "))
		}
		if repeat == "none" {
			attributes["recurrence_rule"] = api.Null
		} else {
			attributes["recurrence_rule"] = repeat
		}
	}
	return attributes, nil
}
