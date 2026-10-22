package commands

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

var cardColors = []string{"red", "orange", "yellow", "green", "blue", "purple"}

func cardFlags() []Flag {
	return []Flag{
		F("description", "TEXT", "Description (plain text, or HTML with --html)"),
		Switch("html", "The description is HTML"),
		F("due", "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none"),
		F("assignee", "USER", "me, none, a user id, email or name"),
		F("color", "COLOR", strings.Join(cardColors, ", ")+" or none"),
	}
}

func boards() []*Definition {
	return []*Definition{
		New("card list", "Show a board: its columns and their cards", []string{"TOOL"},
			[]Flag{Switch("archived", "Show archived cards instead of active ones")}, listCards),
		New("card show", "Show a card with its description, comments and attachments", []string{"TOOL/CARD"}, nil, showCard),
		New("card create", "Add a card to a board (to the first column unless --column)", []string{"TOOL", "TITLE"},
			append(cardFlags(), F("column", "COLUMN", "Column id or name")), createCard),
		New("card update", "Change a card's title, description, due date, assignee or color", []string{"TOOL/CARD"},
			append(cardFlags(), F("title", "TEXT", "New title")), updateCard),
		New("card move", "Move a card to another column, or to a position within its column", []string{"TOOL/CARD", "[COLUMN]"},
			[]Flag{F("position", "N", "Position in the column, 1 = top (default: bottom)")}, moveCard),
		New("card archive", "Archive a card (reversible with card unarchive)", []string{"TOOL/CARD"}, nil, archiveCard),
		New("card unarchive", "Bring an archived card back", []string{"TOOL/CARD"}, nil, unarchiveCard),
		New("card delete", "Delete a card permanently, with its comments and attachments", []string{"TOOL/CARD"}, nil, deleteCard),
		New("card comment", "Comment on a card", []string{"TOOL/CARD", "TEXT"}, []Flag{Switch("html", "TEXT is HTML")}, commentCard),
		New("card uncomment", "Delete a comment from a card: one of your own, or anyone's on a board you own", []string{"TOOL/CARD", "COMMENT"}, nil, uncommentCard),
		New("card attach", "Attach files to a card (25 MB max each)", []string{"TOOL/CARD", "PATH..."}, nil, attachCard),
		New("column create", "Add a column to the end of a board", []string{"TOOL", "NAME"}, nil, createColumn),
		New("column rename", "Rename a column", []string{"TOOL/COLUMN", "NAME"}, nil, renameColumn),
		New("column delete", "Delete a column and every card in it", []string{"TOOL/COLUMN"}, nil, deleteColumn),
	}
}

func listCards(ctx *Ctx, args *Args) error {
	archived := args.On("archived")
	tool, err := ctx.Tool(args.At(0), "boards")
	if err != nil {
		return err
	}
	board, err := ctx.Call("card_list", toolArgs("tool_id", tool.Get("id"), "archived", archived))
	if err != nil {
		return err
	}

	return ctx.Output(board, func() error {
		ctx.Sayf("%s (board %s) %s", tool.Get("name").S(), tool.Get("id").S(), board.Get("url").S())
		for _, column := range board.Get("columns").Items() {
			ctx.Blank()
			ctx.Sayf("%s [column %s]", column.Get("name").S(), column.Get("id").S())
			cards := column.Get("cards").Items()
			if len(cards) == 0 {
				ctx.Sayf("  (no %scards)", If(archived, "archived "))
			}
			var rows [][]string
			for _, card := range cards {
				rows = append(rows, []string{tool.Get("id").S() + "/" + card.Get("id").S(), card.Get("title").S(), cardSummary(card)})
			}
			ctx.Table(rows, 2)
		}
		return nil
	})
}

func showCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	card, err := ctx.Call("card_show", toolArgs("tool_id", tool.Get("id"), "card_id", id))
	if err != nil {
		return err
	}

	return ctx.Output(card, func() error {
		ctx.Sayf("%s (card %s/%s)", card.Get("title").S(), tool.Get("id").S(), card.Get("id").S())
		ctx.Field("Board", tool.Get("name").S()+" › "+card.Get("column", "name").S())
		ctx.Field("Assignee", Person(card.Get("assignee")))
		ctx.Field("Due", card.Get("due_date").S())
		ctx.Field("Color", card.Get("color").S())
		ctx.Field("Archived", If(card.Get("archived").Truthy(), "yes"))
		ctx.Field("Created", Join(" by ", Moment(card.Get("created_at")), card.Get("creator", "name").S()))
		ctx.Field("URL", card.Get("url").S())
		showDetails(ctx, card)
		return nil
	})
}

func createCard(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "boards")
	if err != nil {
		return err
	}
	target, err := findColumn(ctx, tool, args.Value("column"))
	if err != nil {
		return err
	}

	attributes, err := cardAttributes(ctx, tool, args)
	if err != nil {
		return err
	}
	attributes["title"] = args.At(1)
	created := asToolArgs(attributes)
	created["tool_id"], created["column"] = tool.Get("id"), target.Get("id").S()
	card, err := ctx.Call("card_create", created)
	if err != nil {
		return err
	}
	return ctx.Output(card, func() error {
		ctx.Sayf("Created card %s/%s %s in %s: %s", tool.Get("id").S(), card.Get("id").S(), Quoted(card.Get("title").S()),
			target.Get("name").S(), card.Get("url").S())
		return nil
	})
}

func updateCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	attributes, err := cardAttributes(ctx, tool, args)
	if err != nil {
		return err
	}
	if title, ok := args.Flag("title"); ok {
		attributes["title"] = title
	}
	if len(attributes) == 0 {
		return api.Usagef("Nothing to update. See `dobase help card`.")
	}

	changes := asToolArgs(attributes)
	changes["tool_id"], changes["card_id"] = tool.Get("id"), id
	card, err := ctx.Call("card_update", changes)
	if err != nil {
		return err
	}
	return ctx.Output(card, func() error {
		ctx.Sayf("Updated card %s/%s %s.", tool.Get("id").S(), card.Get("id").S(), Quoted(card.Get("title").S()))
		return nil
	})
}

func moveCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	column, hasColumn := args.Get(1), len(args.Positional) > 1
	at, hasPosition := args.Flag("position")
	if !hasColumn && !hasPosition {
		return api.Usagef("Give a COLUMN, a --position, or both.")
	}

	body := map[string]any{"tool_id": tool.Get("id"), "card_id": id}
	if hasColumn {
		target, err := findColumn(ctx, tool, column)
		if err != nil {
			return err
		}
		body["column"] = target.Get("id").S()
	}
	if hasPosition {
		body["position"] = position(at)
	}
	card, err := ctx.Call("card_move", body)
	if err != nil {
		return err
	}
	return ctx.Output(card, func() error {
		ctx.Sayf("Moved card %s/%s %s to %s, position %d.", tool.Get("id").S(), card.Get("id").S(), Quoted(card.Get("title").S()),
			card.Get("column", "name").S(), card.Get("position").Int()+1)
		return nil
	})
}

func archiveCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	card, err := ctx.Call("card_archive", toolArgs("tool_id", tool.Get("id"), "card_id", id))
	if err != nil {
		return err
	}
	return ctx.Output(card, func() error {
		ctx.Sayf("Archived card %s/%s %s.", tool.Get("id").S(), card.Get("id").S(), Quoted(card.Get("title").S()))
		return nil
	})
}

func unarchiveCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	card, err := ctx.Call("card_unarchive", toolArgs("tool_id", tool.Get("id"), "card_id", id))
	if err != nil {
		return err
	}
	return ctx.Output(card, func() error {
		ctx.Sayf("Unarchived card %s/%s %s.", tool.Get("id").S(), card.Get("id").S(), Quoted(card.Get("title").S()))
		return nil
	})
}

func deleteCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	if _, err := ctx.Call("card_delete", toolArgs("tool_id", tool.Get("id"), "card_id", id, "confirm", true)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted card %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func commentCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	body, err := ctx.RichText(args.At(1), args.On("html"))
	if err != nil {
		return err
	}
	comment, err := ctx.Call("card_comment", toolArgs("tool_id", tool.Get("id"), "card_id", id, "text", body, "html", true))
	if err != nil {
		return err
	}
	return ctx.Output(comment, func() error {
		ctx.Sayf("Commented on card %s/%d [comment %s].", tool.Get("id").S(), id, comment.Get("id").S())
		return nil
	})
}

func uncommentCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	return deleteComment(ctx, "card_uncomment", toolArgs("tool_id", tool.Get("id"), "card_id", id), args.At(1), fmt.Sprintf("card %s/%d", tool.Get("id").S(), id))
}

func attachCard(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "card")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/board/cards/%d/attachments", tool.Get("id").S(), id)
	label := fmt.Sprintf("card %s/%d", tool.Get("id").S(), id)
	return attachFiles(ctx, path, args.Rest(1), label)
}

func createColumn(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "boards")
	if err != nil {
		return err
	}
	column, err := ctx.Call("column_create", toolArgs("tool_id", tool.Get("id"), "name", args.At(1)))
	if err != nil {
		return err
	}
	return ctx.Output(column, func() error {
		ctx.Sayf("Created column %s/%s %s.", tool.Get("id").S(), column.Get("id").S(), Quoted(column.Get("name").S()))
		return nil
	})
}

func renameColumn(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "column")
	if err != nil {
		return err
	}
	column, err := ctx.Call("column_rename", toolArgs("tool_id", tool.Get("id"), "column_id", id, "name", args.At(1)))
	if err != nil {
		return err
	}
	return ctx.Output(column, func() error {
		ctx.Sayf("Renamed column %s/%s to %s.", tool.Get("id").S(), column.Get("id").S(), Quoted(column.Get("name").S()))
		return nil
	})
}

func deleteColumn(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "boards", "column")
	if err != nil {
		return err
	}
	if _, err := ctx.Call("column_delete", toolArgs("tool_id", tool.Get("id"), "column_id", id, "confirm", true)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted column %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func cardSummary(card api.Value) string {
	return Join("  ",
		If(!card.Get("due_date").IsNull(), "due "+card.Get("due_date").S()),
		If(card.Get("assignee").Truthy(), "@"+card.Get("assignee", "name").S()),
		card.Get("color").S(),
		If(card.Get("comments_count").Int() > 0, Count(card.Get("comments_count").Int(), "comment")),
		If(card.Get("attachments_count").Int() > 0, Count(card.Get("attachments_count").Int(), "file")),
	)
}

// findColumn is the first column, or the one whose id or name (or the start of it) is reference.
func findColumn(ctx *Ctx, tool api.Value, reference string) (api.Value, error) {
	board, err := ctx.Call("card_list", toolArgs("tool_id", tool.Get("id")))
	if err != nil {
		return api.Null, err
	}
	return findNamed(board.Get("columns").Items(), reference, "name", "column", "Columns", tool.Get("name").S())
}

func cardAttributes(ctx *Ctx, tool api.Value, args *Args) (map[string]any, error) {
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
	if color, ok := args.Flag("color"); ok {
		if !slices.Contains(cardColors, color) && color != "none" {
			return nil, api.Usagef("--color must be one of: %s, none", strings.Join(cardColors, ", "))
		}
		if color == "none" {
			color = ""
		}
		attributes["color"] = color
	}
	return attributes, nil
}

// dueDateParam is a due date for a request body: a date, or null for "none" (to clear it).
func dueDateParam(value string) (api.Value, error) {
	date, err := DateParam(value)
	if err != nil || date == "" {
		return api.Null, err
	}
	return api.Of(date), nil
}
