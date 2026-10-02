// Package command holds what every command shares: its definition (name,
// arguments, flags), the parsed arguments, and a context with the helpers
// commands are written in: API calls, lookups, input parsing and output.
package command

import (
	"fmt"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Run is what a command does.
type Run func(ctx *Ctx, args *Args) error

// Flag is an option. Flags with a placeholder take a value; flags without one are switches.
type Flag struct {
	Name        string
	Placeholder string
	Description string
	// Repeatable flags can be given several times, and keep every value.
	Repeatable bool
}

// F is `--name VALUE`.
func F(name, placeholder, description string) Flag {
	return Flag{Name: name, Placeholder: placeholder, Description: description}
}

// Each is `--name VALUE`, as often as needed: `--attach a.pdf --attach b.pdf`.
func Each(name, placeholder, description string) Flag {
	return Flag{Name: name, Placeholder: placeholder, Description: description, Repeatable: true}
}

// Switch is `--name`.
func Switch(name, description string) Flag {
	return Flag{Name: name, Description: description}
}

// Label is `--flag VALUE` as shown in help.
func (f Flag) Label() string {
	if f.Placeholder == "" {
		return "--" + f.Name
	}
	return "--" + f.Name + " " + f.Placeholder
}

type Definition struct {
	Name    string
	Summary string
	Args    []string
	Flags   []Flag
	Run     Run
}

// New is Definition("card create", "Add a card", []string{"TOOL", "TITLE"}, []Flag{F(..), Switch(..)}, run).
func New(name, summary string, args []string, flags []Flag, run Run) *Definition {
	return &Definition{Name: name, Summary: summary, Args: args, Flags: flags, Run: run}
}

// Usage is "dobase card create TOOL TITLE".
func (d *Definition) Usage() string {
	return strings.Join(append([]string{"dobase", d.Name}, d.Args...), " ")
}

// Noun is "card" for "card create", "" for "login".
func (d *Definition) Noun() string {
	noun, _, ok := strings.Cut(d.Name, " ")
	if !ok {
		return ""
	}
	return noun
}

func (d *Definition) minArgs() int {
	count := 0
	for _, arg := range d.Args {
		if !strings.HasPrefix(arg, "[") {
			count++
		}
	}
	return count
}

func (d *Definition) maxArgs() int {
	for _, arg := range d.Args {
		if strings.HasSuffix(arg, "...") {
			return int(^uint(0) >> 1)
		}
	}
	return len(d.Args)
}

// Help is the usage, summary and flags of the command.
func (d *Definition) Help() string {
	var help strings.Builder
	fmt.Fprintf(&help, "Usage: %s\n\n%s\n", d.Usage(), d.Summary)
	if len(d.Flags) > 0 {
		help.WriteString("\n")
	}
	for _, flag := range d.Flags {
		// Laid out like Ruby's OptionParser, which the first version of the CLI used.
		label := "    " + flag.Label()
		if Width(label) > 32 {
			fmt.Fprintf(&help, "    %s\n    %s %s\n", label, strings.Repeat(" ", 32), flag.Description)
		} else {
			fmt.Fprintf(&help, "    %s %s\n", Ljust(label, 32), flag.Description)
		}
	}
	return help.String()
}

func (d *Definition) flag(name string) (Flag, bool) {
	for _, flag := range d.Flags {
		if flag.Name == name {
			return flag, true
		}
	}
	return Flag{}, false
}

// optionLike says whether name could be the name of an option: letters, digits
// and dashes, starting with a letter.
func optionLike(name string) bool {
	for i := 0; i < len(name); i++ {
		char := name[i]
		letter := ('a' <= char && char <= 'z') || ('A' <= char && char <= 'Z')
		if !letter && (i == 0 || (char != '-' && (char < '0' || char > '9'))) {
			return false
		}
	}
	return name != ""
}

// Parse splits argv into positional arguments and flags, which may come in any
// order. A word is a flag when it's --name or --name=value; anything else is
// an argument, also text that starts with a dash ("- first point", "-5"). Only
// what looks like a flag the command doesn't have is refused. After "--" every
// word is an argument.
func (d *Definition) Parse(argv []string) (*Args, error) {
	args := &Args{values: map[string]string{}, lists: map[string][]string{}}

	for i := 0; i < len(argv); i++ {
		word := argv[i]
		if word == "--" {
			args.Positional = append(args.Positional, argv[i+1:]...)
			break
		}
		if word == "--help" || word == "-h" {
			return nil, &api.Error{Kind: api.Help, Message: d.Help()}
		}

		name, inline, hasInline := strings.Cut(word, "=")
		bare, dashed := strings.CutPrefix(name, "--")
		flag, ok := d.flag(bare)
		if !dashed || (!ok && !optionLike(bare)) {
			args.Positional = append(args.Positional, word)
			continue
		}
		if !ok {
			return nil, api.Usagef("invalid option: %s\n\n%s", word, d.Help())
		}

		switch {
		case flag.Placeholder != "":
			value := inline
			if !hasInline {
				if i+1 >= len(argv) {
					return nil, api.Usagef("missing argument: %s\n\n%s", name, d.Help())
				}
				i++
				value = argv[i]
			}
			args.values[flag.Name] = value
			if flag.Repeatable {
				args.lists[flag.Name] = append(args.lists[flag.Name], value)
			}
		case hasInline:
			return nil, api.Usagef("needless argument: %s\n\n%s", word, d.Help())
		default:
			args.values[flag.Name] = ""
		}
	}

	if len(args.Positional) < d.minArgs() || len(args.Positional) > d.maxArgs() {
		return nil, &api.Error{Kind: api.Usage, Message: d.Help()}
	}
	return args, nil
}

// Args are the parsed arguments of a command.
type Args struct {
	Positional []string
	values     map[string]string
	lists      map[string][]string
}

// At is a required positional argument.
func (a *Args) At(index int) string { return a.Positional[index] }

// Get is an optional positional argument, or "".
func (a *Args) Get(index int) string {
	if index < len(a.Positional) {
		return a.Positional[index]
	}
	return ""
}

// Rest are the positional arguments from index on, for `PATH...`.
func (a *Args) Rest(index int) []string {
	if index < len(a.Positional) {
		return a.Positional[index:]
	}
	return nil
}

// Flag is the value of a `--name VALUE` flag, and whether it was given.
func (a *Args) Flag(name string) (string, bool) {
	value, ok := a.values[name]
	return value, ok
}

// All are the values of a repeatable flag, in the order they were given.
func (a *Args) All(name string) []string { return a.lists[name] }

// Value is the value of a `--name VALUE` flag, or "".
func (a *Args) Value(name string) string { return a.values[name] }

// On says whether a `--name` switch (or flag) was given.
func (a *Args) On(name string) bool {
	_, ok := a.values[name]
	return ok
}

// Any says whether any of these flags or switches was given.
func (a *Args) Any(names ...string) bool {
	for _, name := range names {
		if a.On(name) {
			return true
		}
	}
	return false
}
