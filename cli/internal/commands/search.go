package commands

import (
	"strings"
	"unicode/utf8"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func search() []*Definition {
	return []*Definition{
		New("search", "Find cards, todos, documents, files, messages, events and mail that match", []string{"QUERY..."}, nil, runSearch),
	}
}

func runSearch(ctx *Ctx, args *Args) error {
	query := strings.TrimSpace(strings.Join(args.Rest(0), " "))
	if utf8.RuneCountInString(query) < 2 {
		return api.Usagef("Give at least two characters to search for.")
	}

	result, err := ctx.Get("/search", "q", query)
	if err != nil {
		return err
	}
	return ctx.Output(result, func() error {
		results := result.Get("results").Items()
		if len(results) == 0 {
			ctx.Sayf("Nothing matches \"%s\".", query)
		}
		var rows [][]string
		for _, hit := range results {
			rows = append(rows, []string{hit.Get("kind").S(), hit.Get("title").S(), hit.Get("tool_name").S(), hit.Get("url").S()})
		}
		ctx.Table(rows, 0)
		return nil
	})
}
