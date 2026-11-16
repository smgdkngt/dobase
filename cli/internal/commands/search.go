package commands

import (
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

// The kinds of result there are, as the server names them
var searchKinds = []string{"card", "todo", "document", "folder", "file", "message", "event", "mail"}

func search() []*Definition {
	return []*Definition{
		New("search", "Find cards, todos, documents, files, messages, events and mail that match", []string{"QUERY..."},
			[]Flag{F("kind", "KIND", "Every result of one kind instead of a few of each: "+strings.Join(searchKinds, ", "))}, runSearch),
	}
}

func runSearch(ctx *Ctx, args *Args) error {
	query := strings.TrimSpace(strings.Join(args.Rest(0), " "))
	if utf8.RuneCountInString(query) < 2 {
		return api.Usagef("Give at least two characters to search for.")
	}
	kind, hasKind := args.Flag("kind")
	if hasKind && !slices.Contains(searchKinds, kind) {
		return api.Usagef("--kind is one of %s.", strings.Join(searchKinds, ", "))
	}

	call := toolArgs("query", query)
	if hasKind {
		call["kind"] = kind
	}
	result, err := ctx.Call("search", call)
	if err != nil {
		return err
	}
	return ctx.Output(result, func() error {
		results := result.Get("results").Items()
		if len(results) == 0 {
			ctx.Sayf("Nothing matches \"%s\".", query)
		}
		var rows [][]string
		shown := map[string]int64{}
		for _, hit := range results {
			title := hit.Get("title").S()
			if hit.Get("archived").Truthy() {
				title += " (archived)"
			}
			date := hit.Get("date").S()
			if len(date) >= 10 {
				date = date[:10]
			}
			shown[hit.Get("kind").S()]++
			rows = append(rows, []string{hit.Get("kind").S(), title, hit.Get("tool_name").S(), date, hit.Get("url").S()})
		}
		ctx.Table(rows, 0)
		if !hasKind {
			for _, each := range searchKinds {
				if total := result.Get("totals", each).Int(); total > shown[each] {
					ctx.Sayf("%d of %d %ss shown: dobase search --kind %s %s", shown[each], total, each, each, query)
				}
			}
		}
		return nil
	})
}
