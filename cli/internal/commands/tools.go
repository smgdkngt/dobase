package commands

import (
	"slices"
	"sort"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

var toolTypes = []string{"boards", "todos", "docs", "chat", "files", "mail", "calendar", "room"}

func tools() []*Definition {
	return []*Definition{
		New("tool list", "List your tools (* = new activity since you last looked)", nil,
			[]Flag{F("type", "TYPE", "Only tools of this type: "+strings.Join(toolTypes, ", "))}, listTools),
		New("tool show", "Show a tool, your role and its collaborators", []string{"TOOL"}, nil, showTool),
		New("tool create", "Create a tool (mail and calendar still need their account connected in the browser)",
			[]string{"TYPE", "NAME"}, nil, createTool),
		New("tool rename", "Rename a tool (owners only)", []string{"TOOL", "NAME"}, nil, renameTool),
	}
}

func listTools(ctx *Ctx, args *Args) error {
	all, err := ctx.Get("/tools")
	if err != nil {
		return err
	}
	var list []api.Value
	for _, tool := range all.Items() {
		if kind, ok := args.Flag("type"); !ok || tool.Get("type").S() == kind {
			list = append(list, tool)
		}
	}

	return ctx.Output(api.Of(list), func() error {
		if len(list) == 0 {
			ctx.Say("No tools.")
		}
		sort.SliceStable(list, func(i, j int) bool {
			a, b := list[i], list[j]
			if a.Get("type").S() != b.Get("type").S() {
				return a.Get("type").S() < b.Get("type").S()
			}
			return strings.ToLower(a.Get("name").S()) < strings.ToLower(b.Get("name").S())
		})
		var rows [][]string
		for _, tool := range list {
			rows = append(rows, []string{tool.Get("id").S(), tool.Get("type").S(), tool.Get("name").S() + If(tool.Get("unread").Truthy(), " *")})
		}
		ctx.Table(rows, 0)
		return nil
	})
}

func showTool(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "")
	if err != nil {
		return err
	}
	details, err := ctx.Get("/tools/" + tool.Get("id").S())
	if err != nil {
		return err
	}

	return ctx.Output(details, func() error {
		ctx.Sayf("%s (%s %s)", details.Get("name").S(), details.Get("type").S(), details.Get("id").S())
		ctx.Field("Your role", details.Get("role").S())
		ctx.Field("URL", details.Get("url").S())
		ctx.Blank()
		ctx.Say("Collaborators:")
		var rows [][]string
		for _, user := range details.Get("collaborators").Items() {
			rows = append(rows, []string{user.Get("id").S(), Person(user), user.Get("role").S()})
		}
		ctx.Table(rows, 2)
		return nil
	})
}

func createTool(ctx *Ctx, args *Args) error {
	kind, name := args.At(0), args.At(1)
	if !slices.Contains(toolTypes, kind) {
		return api.Usagef("TYPE must be one of: %s", strings.Join(toolTypes, ", "))
	}

	created, err := ctx.Post("/tools", map[string]any{"tool": map[string]any{"name": name, "tool_type": kind}})
	if err != nil {
		return err
	}
	return ctx.Output(created, func() error {
		ctx.Sayf("Created %s tool %s (%s): %s", created.Get("type").S(), Quoted(created.Get("name").S()), created.Get("id").S(), created.Get("url").S())
		return nil
	})
}

func renameTool(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "")
	if err != nil {
		return err
	}
	updated, err := ctx.Patch("/tools/"+tool.Get("id").S(), map[string]any{"tool": map[string]any{"name": args.At(1)}})
	if err != nil {
		return err
	}
	return ctx.Output(updated, func() error {
		ctx.Sayf("Renamed tool %s to %s.", updated.Get("id").S(), Quoted(updated.Get("name").S()))
		return nil
	})
}
