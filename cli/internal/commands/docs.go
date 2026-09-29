package commands

import (
	"fmt"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func contentFlags() []Flag {
	return []Flag{F("content", "TEXT", "Content (plain text, or HTML with --html)"), Switch("html", "The content is HTML")}
}

func docs() []*Definition {
	return []*Definition{
		New("doc list", "List the documents in a docs tool, last edited first", []string{"TOOL"}, nil, listDocs),
		New("doc show", "Show a document with its content", []string{"TOOL/DOC"},
			[]Flag{Switch("html", "Print the content as HTML instead of plain text")}, showDoc),
		New("doc create", "Create a document", []string{"TOOL", "TITLE"}, contentFlags(), createDoc),
		New("doc update", "Rename a document or replace its content (refused while someone else is editing it)", []string{"TOOL/DOC"},
			append([]Flag{F("title", "TEXT", "New title")}, contentFlags()...), updateDoc),
		New("doc delete", "Delete a document permanently", []string{"TOOL/DOC"}, nil, deleteDoc),
	}
}

func listDocs(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "docs")
	if err != nil {
		return err
	}
	docs, err := ctx.Get(fmt.Sprintf("/tools/%s/docs", tool.Get("id").S()))
	if err != nil {
		return err
	}

	return ctx.Output(docs, func() error {
		ctx.Sayf("%s (docs %s) %s", tool.Get("name").S(), tool.Get("id").S(), docs.Get("url").S())
		ctx.Blank()
		documents := docs.Get("documents").Items()
		if len(documents) == 0 {
			ctx.Say("  (no documents)")
		}
		var rows [][]string
		for _, document := range documents {
			rows = append(rows, []string{tool.Get("id").S() + "/" + document.Get("id").S(), document.Get("title").S(), documentSummary(document)})
		}
		ctx.Table(rows, 2)
		return nil
	})
}

func showDoc(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "docs", "doc")
	if err != nil {
		return err
	}
	document, err := ctx.Get(fmt.Sprintf("/tools/%s/docs/documents/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	return ctx.Output(document, func() error {
		ctx.Sayf("%s (doc %s/%s)", document.Get("title").S(), tool.Get("id").S(), document.Get("id").S())
		ctx.Field("Docs", tool.Get("name").S())
		ctx.Field("Editing", If(document.Get("locked").Truthy(), document.Get("locked_by", "name").S()+" has it open in the editor"))
		ctx.Field("Created", Join(" by ", Moment(document.Get("created_at")), document.Get("creator", "name").S()))
		ctx.Field("Updated", Join(" by ", Moment(document.Get("updated_at")), document.Get("updated_by", "name").S()))
		ctx.Field("URL", document.Get("url").S())
		ctx.Blank()

		content := document.Get("content").S()
		if args.On("html") {
			content = document.Get("content_html").S()
		}
		if isBlank(content) {
			content = "(empty)"
		}
		ctx.Say(content)
		return nil
	})
}

func createDoc(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "docs")
	if err != nil {
		return err
	}
	attributes := map[string]any{"title": args.At(1)}
	if content, ok := args.Flag("content"); ok {
		if attributes["content"], err = ctx.RichText(content, args.On("html")); err != nil {
			return err
		}
	}

	document, err := ctx.Post(fmt.Sprintf("/tools/%s/docs/documents", tool.Get("id").S()), map[string]any{"docs_document": attributes})
	if err != nil {
		return err
	}
	return ctx.Output(document, func() error {
		ctx.Sayf("Created doc %s/%s %s: %s", tool.Get("id").S(), document.Get("id").S(), Quoted(document.Get("title").S()), document.Get("url").S())
		return nil
	})
}

func updateDoc(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "docs", "doc")
	if err != nil {
		return err
	}
	attributes := map[string]any{}
	if title, ok := args.Flag("title"); ok {
		attributes["title"] = title
	}
	if content, ok := args.Flag("content"); ok {
		if attributes["content"], err = ctx.RichText(content, args.On("html")); err != nil {
			return err
		}
	}
	if len(attributes) == 0 {
		return api.Usagef("Nothing to update. See `dobase help doc`.")
	}

	document, err := ctx.Patch(fmt.Sprintf("/tools/%s/docs/documents/%d", tool.Get("id").S(), id), map[string]any{"docs_document": attributes})
	if err != nil {
		return err
	}
	return ctx.Output(document, func() error {
		ctx.Sayf("Updated doc %s/%s %s.", tool.Get("id").S(), document.Get("id").S(), Quoted(document.Get("title").S()))
		return nil
	})
}

func deleteDoc(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "docs", "doc")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/docs/documents/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted doc %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func documentSummary(document api.Value) string {
	edited := ""
	if at := Moment(document.Get("updated_at")); at != "" {
		edited = "edited " + at
	}
	return Join("  ",
		Join(" by ", edited, document.Get("updated_by", "name").S()),
		If(document.Get("locked").Truthy(), document.Get("locked_by", "name").S()+" is editing"),
	)
}
