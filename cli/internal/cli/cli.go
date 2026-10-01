// Package cli finds the command in the arguments, runs it, and prints help.
package cli

import (
	"fmt"
	"io"
	"os"
	"slices"
	"sort"
	"strings"

	"golang.org/x/term"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/commands"
	"github.com/smgdkngt/dobase/cli/internal/config"
	"github.com/smgdkngt/dobase/cli/internal/tui"
)

// Version is set at build time: go build -ldflags "-X github.com/smgdkngt/dobase/cli/internal/cli.Version=2026.09.24".
var Version = "dev"

const intro = `dobase: work in your Dobase tools from the command line.

Usage: dobase NOUN VERB [ARGS] [OPTIONS] [--json]

TOOL is a tool id or (part of) its name. Things inside a tool are TOOL/ID,
e.g. 12/104; list commands print these references. A TEXT value of "-" is
read from stdin. --json prints the raw API response instead of text. After
"--" everything is an argument, for a TEXT such as "--force".
` + "`dobase help NOUN`" + ` shows the options of every command for that noun.`

func init() {
	commands.RunApp = func(ctx *command.Ctx) error { return tui.Run(ctx.Config, ctx.UserAgent) }
}

func userAgent() string { return "dobase-cli/" + Version }

// Run runs the CLI and returns its exit status.
func Run(argv []string, out, errOut io.Writer) int {
	definitions := commands.Definitions()
	argv, json := withoutJSON(argv)

	first := ""
	if len(argv) > 0 {
		first = argv[0]
	}
	switch {
	// A person at a terminal gets the app; scripts and pipes get the help.
	case len(argv) == 0 && !json && term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd())):
		if err := tui.Run(&config.Config{}, userAgent()); err != nil {
			fmt.Fprintf(errOut, "Error: %s\n", command.Clean(err.Error()))
			return 1
		}
		return 0
	case len(argv) == 0 || first == "help" || first == "--help" || first == "-h":
		noun := ""
		if len(argv) > 1 {
			noun = argv[1]
		}
		help(definitions, noun, out)
		return 0
	case first == "--version" || first == "version":
		fmt.Fprintf(out, "dobase %s\n", Version)
		return 0
	}

	definition, rest := find(definitions, argv)
	if definition == nil {
		fmt.Fprintf(errOut, "Unknown command: dobase %s\n\n", strings.Join(argv, " "))
		help(definitions, first, out)
		return 2
	}

	args, err := definition.Parse(rest)
	if err == nil {
		ctx := command.NewCtx(&config.Config{}, out, json, userAgent())
		err = definition.Run(ctx, args)
	}
	if err == nil {
		return 0
	}
	switch api.KindOf(err) {
	case api.Help:
		fmt.Fprint(out, err.Error())
		return 0
	case api.Usage:
		fmt.Fprintln(errOut, command.Clean(strings.TrimRight(err.Error(), " \t\r\n")))
		return 2
	}
	fmt.Fprintf(errOut, "Error: %s\n", command.Clean(err.Error()))
	return 1
}

// withoutJSON takes --json out of the arguments and says whether it was there.
// After "--" it's an argument like any other.
func withoutJSON(argv []string) ([]string, bool) {
	end := slices.Index(argv, "--")
	if end < 0 {
		end = len(argv)
	}
	options := slices.DeleteFunc(slices.Clone(argv[:end]), func(arg string) bool { return arg == "--json" })
	return append(options, argv[end:]...), len(options) < end
}

func find(definitions []*command.Definition, argv []string) (*command.Definition, []string) {
	if len(argv) >= 2 {
		name := argv[0] + " " + argv[1]
		for _, definition := range definitions {
			if definition.Name == name {
				return definition, argv[2:]
			}
		}
	}
	for _, definition := range definitions {
		if definition.Name == argv[0] {
			return definition, argv[1:]
		}
	}
	return nil, nil
}

type group struct {
	noun    string
	members []*command.Definition
}

// groups are the commands by noun: general ones first, then tools, then the rest by name.
func groups(definitions []*command.Definition) []group {
	var groups []group
	for _, definition := range definitions {
		index := slices.IndexFunc(groups, func(g group) bool { return g.noun == definition.Noun() })
		if index < 0 {
			groups = append(groups, group{noun: definition.Noun()})
			index = len(groups) - 1
		}
		groups[index].members = append(groups[index].members, definition)
	}
	rank := func(noun string) int {
		switch noun {
		case "":
			return 0
		case "tool":
			return 1
		}
		return 2
	}
	sort.SliceStable(groups, func(i, j int) bool {
		a, b := groups[i].noun, groups[j].noun
		if rank(a) != rank(b) {
			return rank(a) < rank(b)
		}
		return rank(a) == 2 && a < b
	})
	return groups
}

func help(definitions []*command.Definition, noun string, out io.Writer) {
	summary := func(noun string) string {
		for _, n := range commands.Nouns() {
			if n.Name == noun {
				return n.Summary
			}
		}
		return ""
	}
	groups := groups(definitions)

	if noun != "" {
		for _, g := range groups {
			if g.noun != noun {
				continue
			}
			fmt.Fprintf(out, "%s: %s\n\n", noun, summary(noun))
			for _, definition := range g.members {
				fmt.Fprintf(out, "  %s\n", definition.Usage())
				fmt.Fprintf(out, "      %s\n", definition.Summary)
				for _, flag := range definition.Flags {
					fmt.Fprintf(out, "      %s %s\n", command.Ljust(flag.Label(), 26), flag.Description)
				}
				fmt.Fprintln(out)
			}
			return
		}
	}

	fmt.Fprintln(out, intro)
	for _, g := range groups {
		fmt.Fprintln(out)
		if g.noun == "" {
			fmt.Fprintln(out, "General")
		} else {
			fmt.Fprintf(out, "%s: %s\n", g.noun, summary(g.noun))
		}
		width := 0
		for _, definition := range g.members {
			width = max(width, command.Width(definition.Usage()))
		}
		for _, definition := range g.members {
			fmt.Fprintf(out, "  %s  %s\n", command.Ljust(definition.Usage(), width), definition.Summary)
		}
	}
}
