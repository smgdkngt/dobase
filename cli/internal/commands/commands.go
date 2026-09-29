// Package commands holds every command, by noun. `dobase help` lists them in
// this order within a noun.
package commands

import "github.com/smgdkngt/dobase/cli/internal/command"

// Definitions are all commands.
func Definitions() []*command.Definition {
	var all []*command.Definition
	for _, noun := range [][]*command.Definition{
		account(),
		boards(),
		calendar(),
		chat(),
		docs(),
		files(),
		mail(),
		notifications(),
		search(),
		todos(),
		tools(),
	} {
		all = append(all, noun...)
	}
	return all
}

// Noun is what a noun is, shown in `dobase help`.
type Noun struct{ Name, Summary string }

func Nouns() []Noun {
	return []Noun{
		{"card", "Cards on a board (boards tools)"},
		{"column", "Columns on a board (boards tools)"},
		{"event", "Events in a calendar (calendar tools)"},
		{"calendar", "The calendars of a calendar tool, and syncing them"},
		{"chat", "Messages in a chat (chat tools)"},
		{"doc", "Documents (docs tools)"},
		{"file", "Files and their downloads (files tools)"},
		{"folder", "Folders of files (files tools)"},
		{"mail", "Email in mail tools: conversations, flags, drafts and sending"},
		{"notification", "Your notifications"},
		{"search", "Search every tool you share"},
		{"todo", "Todos on lists (todos tools)"},
		{"todolist", "Lists in a todos tool"},
		{"tool", "The tools you have access to"},
	}
}
