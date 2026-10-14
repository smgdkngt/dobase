package tui

// Mail, to read: conversations per folder, each opened as a whole thread.

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

var mailHints = []hint{{"↑↓", "choose"}, {"enter", "read"}, {"f", "folder"}, {"o", "browser"}, {"esc", "home"}}

var mailHelp = []hint{
	{"↑ ↓ / j k", "Choose a conversation"},
	{"enter", "Read it (this doesn't mark it read)"},
	{"f", "Next folder: inbox, starred, sent, archive, drafts, junk"},
	{"o", "Open it in your browser to reply"},
	{"r", "Reload"},
	{"esc", "Back home"},
}

// Junk is a folder only for an account whose mail server has one (the mailbox's "folders").
var mailFolders = []string{"inbox", "starred", "sent", "archive", "drafts", "junk"}

type Mail struct {
	notLive
	tool     api.Value
	mailbox  api.Value
	folder   string
	selected int
}

func loadMail(app *App, tool api.Value, folder string) (*Mail, error) {
	mailbox, err := app.get(toolPath(tool)+"/mails", api.Param{Name: "folder", Value: folder})
	if err != nil {
		return nil, err
	}
	return &Mail{tool: tool, mailbox: mailbox, folder: folder}, nil
}

// folders are the folders this account's mailbox has, in the order f goes through them.
func (s *Mail) folders() []string {
	has := map[string]bool{}
	for _, folder := range s.mailbox.Get("folders").Items() {
		has[folder.S()] = true
	}
	var folders []string
	for _, folder := range mailFolders {
		if folder != "junk" || has[folder] {
			folders = append(folders, folder)
		}
	}
	return folders
}

func (s *Mail) Tool() (api.Value, bool)    { return s.tool, true }
func (s *Mail) Hints() []hint              { return mailHints }
func (s *Mail) Help() []hint               { return mailHelp }
func (s *Mail) conversations() []api.Value { return s.mailbox.Get("conversations").Items() }

func (s *Mail) Refresh() Job {
	tool, folder, selected := s.tool, s.folder, s.selected
	return func(app *App) error {
		fresh, err := loadMail(app, tool, folder)
		if err != nil {
			return err
		}
		fresh.selected = selected
		app.screen = fresh
		return nil
	}
}

func (s *Mail) Key(key Key, view *View, fx *Fx) bool {
	tool := s.tool.Get("id").Int()
	conversations := s.conversations()
	switch {
	case key.Is('f'):
		folders := s.folders()
		next, toolValue := folders[(slices.Index(folders, s.folder)+1)%len(folders)], s.tool
		fx.job("Opening "+next, func(app *App) error {
			fresh, err := loadMail(app, toolValue, next)
			if err != nil {
				return err
			}
			app.screen = fresh
			return nil
		})
	case key.Code == KeyEnter:
		if s.selected < len(conversations) {
			id := conversations[s.selected].Get("id").Int()
			fx.job("Opening the conversation", func(app *App) error {
				detail, err := conversationDetail(app, tool, id)
				if err != nil {
					return err
				}
				app.popup = detail
				return nil
			})
		}
	case key.Is('o'):
		url := fmt.Sprintf("/tools/%d/mails", tool)
		if s.selected < len(conversations) {
			url = fmt.Sprintf("/tools/%d/mails/%s", tool, conversations[s.selected].Get("id").S())
		}
		fx.openURL = &url
	default:
		return moveSelection(&s.selected, len(conversations), key)
	}
	return true
}

func (s *Mail) Draw(b *Buffer, area Rect, view *View) {
	var tabs []Span
	for _, folder := range s.folders() {
		style := dim()
		if folder == s.folder {
			style = Style{}.Fg(accent()).With(Bold | Underlined)
		}
		tabs = append(tabs, Styled(folder, style), Raw("  "))
	}
	name, address := s.tool.Get("name").S(), s.mailbox.Get("account", "email_address").S()
	title := toolIcon("mail") + " " + name
	if address != "" && !strings.EqualFold(name, address) {
		title += " · " + address
	}
	block := panel(title, true)
	bottom := LineOf(tabs...).RightAligned()
	block.TitleBottom = &bottom

	conversations := s.conversations()
	if len(conversations) == 0 {
		message := "Nothing in here."
		if s.folder == "inbox" {
			message = "Inbox zero. Go outside 🌳"
		}
		Paragraph{Lines: []Line{RawLine(message)}, Style: dim(), Block: block}.Render(b, area)
		return
	}
	width := sat(area.W - 4)
	items := make([]ListItem, len(conversations))
	for i, conversation := range conversations {
		unread := !conversation.Get("read").Truthy()
		from := conversation.Get("from").S()
		if conversation.Get("draft").Truthy() {
			from = "Draft"
		}
		badges := ""
		if conversation.Get("starred").Truthy() {
			badges += " ⭐"
		}
		if conversation.Get("has_attachments").Truthy() {
			badges += " 📎"
		}
		if count := conversation.Get("messages_count").Int(); count > 1 {
			badges += fmt.Sprintf(" (%d)", count)
		}
		style, dot := Style{}, "  "
		if unread {
			style, dot = bold(), "● "
		}
		items[i] = Item(
			LineOf(
				Styled(dot, Style{}.Fg(accent())),
				Styled(truncate(from, width/2), style),
				Styled("  "+ago(conversation.Get("sent_at"))+badges, dim())),
			LineOf(Styled("  "+truncate(conversation.Get("subject").S(), sat(width-2)), style)))
	}
	s.selected = min(s.selected, len(items)-1)
	List{Items: items, Block: block, Highlight: selected()}.Render(b, area, s.selected)
}

func conversationDetail(app *App, tool, id int64) (*Detail, error) {
	conversation, err := app.get(fmt.Sprintf("/tools/%d/mails/%d", tool, id))
	if err != nil {
		return nil, err
	}
	var lines []Line
	for _, message := range conversation.Get("messages").Items() {
		from := message.Get("from_address").S()
		if name := message.Get("from_name").S(); name != "" {
			from = fmt.Sprintf("%s <%s>", name, message.Get("from_address").S())
		}
		heading(&lines, from)
		var to []string
		for _, address := range message.Get("to").Items() {
			to = append(to, address.S())
		}
		field(&lines, "To", strings.Join(to, ", "))
		field(&lines, "Sent", ago(message.Get("sent_at")))
		lines = append(lines, RawLine(""))
		addText(&lines, message.Get("body").S(), 0)
		if attachments := message.Get("attachments").Items(); len(attachments) > 0 {
			names := make([]string, len(attachments))
			for i, attachment := range attachments {
				names[i] = attachment.Get("filename").S()
			}
			lines = append(lines, StyledLine("📎 "+strings.Join(names, ", "), dim()))
		}
	}
	return &Detail{
		title: truncate(conversation.Get("subject").S(), 80),
		lines: lines,
		url:   ptr(fmt.Sprintf("/tools/%d/mails/%d", tool, id)),
	}, nil
}
