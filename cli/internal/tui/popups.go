package tui

// Popups over the current screen: help, details, text input, confirmation,
// search and notifications.

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

// Popup is one of the popups below.
type Popup any

type HelpPopup struct{ keys []hint }

// Detail is a card, todo, message or file, with its text; it can take a comment.
type Detail struct {
	title   string
	lines   []Line
	scroll  int
	url     *string
	comment *CommentOn
}

// CommentOn is where a comment goes, and how to show the detail again afterwards.
type CommentOn struct {
	path   string
	reload func(app *App) (*Detail, error)
}

// Submit runs with the text of an input popup.
type Submit func(app *App, text string) error

type InputPopup struct {
	title       string
	placeholder string
	label       string
	input       TextInput
	submit      Submit
}

type ConfirmPopup struct {
	question string
	label    string
	job      Job
}

type SearchPopup struct {
	input       TextInput
	searchedFor string
	results     []api.Value
	selected    int
}

type NotificationsPopup struct {
	items    []api.Value
	selected int
}

// inputPopup asks for one line of text; submit runs as a job with label by the spinner.
func inputPopup(title, placeholder, label string, submit Submit) *InputPopup {
	return &InputPopup{title: title, placeholder: placeholder, label: label, submit: submit}
}

// prefilled starts the field with text, for editing.
func (p *InputPopup) prefilled(text string) *InputPopup {
	p.input = textInputWith(text)
	return p
}

func confirmPopup(question, label string, job Job) *ConfirmPopup {
	return &ConfirmPopup{question: question, label: label, job: job}
}

func popupKey(popup Popup, key Key, fx *Fx) {
	switch p := popup.(type) {
	case *HelpPopup:
		if key.OneOf(KeyEsc, KeyEnter) || key.Is('q', '?') {
			fx.closePopup = true
		}
	case *Detail:
		switch {
		case key.OneOf(KeyEsc, KeyEnter) || key.Is('q'):
			fx.closePopup = true
		case key.Code == KeyDown || key.Is('j'):
			p.scroll++
		case key.Code == KeyUp || key.Is('k'):
			p.scroll = sat(p.scroll - 1)
		case key.Code == KeyPageDown || key.Is(' '):
			p.scroll += 10
		case key.Code == KeyPageUp:
			p.scroll = sat(p.scroll - 10)
		case key.Is('o'):
			fx.openURL = p.url
		case key.Is('c'):
			if p.comment != nil {
				comment := *p.comment
				fx.popup = inputPopup("New comment", "Write a comment and press enter", "Posting your comment", func(app *App, text string) error {
					if _, err := app.post(comment.path, api.Object("body", command.Paragraphs(text))); err != nil {
						return err
					}
					detail, err := comment.reload(app)
					if err != nil {
						return err
					}
					app.popup = detail
					app.say("Comment posted 💬", ToneSuccess)
					return nil
				})
			}
		}
	case *InputPopup:
		switch key.Code {
		case KeyEsc:
			fx.closePopup = true
		case KeyEnter:
			if !p.input.IsBlank() && p.submit != nil {
				submit := p.submit
				p.submit = nil
				text := strings.TrimSpace(p.input.Text())
				fx.closePopup = true
				fx.job(p.label, func(app *App) error { return submit(app, text) })
			}
		default:
			p.input.Key(key)
		}
	case *ConfirmPopup:
		fx.closePopup = true
		if key.Is('y', 'Y') || key.Code == KeyEnter {
			if p.job != nil {
				fx.job(p.label, p.job)
				p.job = nil
			}
		}
	case *SearchPopup:
		switch key.Code {
		case KeyEsc:
			fx.closePopup = true
		case KeyDown:
			p.selected = min(p.selected+1, sat(len(p.results)-1))
		case KeyUp:
			p.selected = sat(p.selected - 1)
		case KeyEnter:
			query := strings.TrimSpace(p.input.Text())
			if query != p.searchedFor && len([]rune(query)) >= 2 {
				p.searchedFor = query
				fx.job("Searching for “"+query+"”", func(app *App) error {
					found, err := app.get("/search", api.Param{Name: "q", Value: query})
					if err != nil {
						return err
					}
					if search, ok := app.popup.(*SearchPopup); ok {
						search.results = slices.Clone(found.Get("results").Items())
						search.selected = 0
					}
					return nil
				})
			} else if p.selected < len(p.results) {
				if url := p.results[p.selected].Get("url"); !url.IsNull() {
					fx.openLink = ptr(url.S())
				}
				fx.closePopup = true
			}
		default:
			p.input.Key(key)
		}
	case *NotificationsPopup:
		switch {
		case key.Code == KeyEsc || key.Is('q', 'n'):
			fx.closePopup = true
		case key.Code == KeyDown || key.Is('j'):
			p.selected = min(p.selected+1, sat(len(p.items)-1))
		case key.Code == KeyUp || key.Is('k'):
			p.selected = sat(p.selected - 1)
		case key.Code == KeyEnter:
			if p.selected < len(p.items) {
				openNotification(&p.items[p.selected], fx)
				fx.closePopup = true
			}
		case key.Is('x'):
			if p.selected < len(p.items) {
				p.items[p.selected] = p.items[p.selected].With("read", true)
				id := p.items[p.selected].Get("id").S()
				fx.job("Marking it read", func(app *App) error {
					_, err := app.post("/notifications/"+id+"/read", api.Object())
					return err
				})
			}
		case key.Is('a'):
			for i := range p.items {
				p.items[i] = p.items[i].With("read", true)
			}
			fx.job("Marking everything read", func(app *App) error {
				result, err := app.post("/notification_reads", api.Object())
				if err != nil {
					return err
				}
				app.say(fmt.Sprintf("Marked %d read. Inbox zero! 🧘", result.Get("marked_as_read").Int()), ToneSuccess)
				return nil
			})
		}
	}
}

func popupHints(popup Popup) []hint {
	switch p := popup.(type) {
	case *HelpPopup:
		return []hint{{"esc", "close"}}
	case *Detail:
		hints := []hint{{"↑↓", "scroll"}, {"o", "open in browser"}}
		if p.comment != nil {
			hints = append(hints, hint{"c", "comment"})
		}
		return append(hints, hint{"esc", "close"})
	case *InputPopup:
		return []hint{{"enter", "save"}, {"esc", "cancel"}}
	case *ConfirmPopup:
		return []hint{{"y", "yes"}, {"n", "no"}}
	case *SearchPopup:
		return []hint{{"enter", "search / open"}, {"↑↓", "choose"}, {"esc", "close"}}
	case *NotificationsPopup:
		return []hint{{"enter", "open"}, {"x", "mark read"}, {"a", "mark all read"}, {"esc", "close"}}
	}
	return nil
}

func drawPopup(popup Popup, b *Buffer) {
	screen := b.Area
	switch p := popup.(type) {
	case *HelpPopup:
		area := popupArea(b, "Keys", 64, len(p.keys)+9)
		var lines []Line
		for _, pair := range p.keys {
			lines = append(lines, LineOf(
				Styled(fmt.Sprintf("  %-14s", pair.key), Style{}.Fg(accent()).With(Bold)),
				Raw(pair.action)))
		}
		lines = append(lines,
			RawLine(""),
			StyledLine("  Everywhere: / search  n notifications  ] [ next tool", dim()),
			StyledLine("  o browser  r reload  esc home  ctrl-c quit", dim()),
			RawLine(""),
			StyledLine("  For scripts and Claude: dobase help", dim()))
		Paragraph{Lines: lines}.Render(b, area)
	case *Detail:
		width := min(max(screen.W*3/4, 50), 100)
		area := popupArea(b, truncate(p.title, width-6), width, sat(screen.H-4))
		total := wrappedHeight(p.lines, area.W)
		p.scroll = min(p.scroll, sat(total-area.H))
		Paragraph{Lines: p.lines, Wrap: true, Scroll: p.scroll}.Render(b, area)
	case *InputPopup:
		area := popupArea(b, p.title, 70, 5)
		rows := splitVertical(area, Length(1), Length(1), Length(1))
		field, hintRow := rows[0], rows[2]
		b.RenderSpan(Styled("› ", Style{}.Fg(accent())), field)
		field = Rect{field.X + 2, field.Y, sat(field.W - 2), field.H}
		p.input.Render(b, field, p.placeholder, true)
		b.RenderLine(StyledLine("enter to save · esc to cancel", dim()), hintRow)
	case *ConfirmPopup:
		area := popupArea(b, "Sure?", 60, 5)
		lines := []Line{RawLine(p.question), RawLine(""), StyledLine("y yes · any other key no", dim())}
		Paragraph{Lines: lines, Wrap: true, Trim: true}.Render(b, area)
	case *SearchPopup:
		area := popupArea(b, "🔎 Search everything", 76, min(sat(screen.H-6), 24))
		rows := splitVertical(area, Length(1), Length(1), Min(1))
		field, results := rows[0], rows[2]
		b.RenderSpan(Styled("› ", Style{}.Fg(accent())), field)
		field = Rect{field.X + 2, field.Y, sat(field.W - 2), field.H}
		p.input.Render(b, field, "Cards, todos, docs, files, chat, events, mail…", true)

		if len(p.results) == 0 {
			message := "Nothing found. Try another word? 🤔"
			if p.searchedFor == "" {
				message = "Type at least two letters and press enter."
			}
			b.RenderLine(StyledLine(message, dim()), results)
			return
		}
		items := make([]ListItem, len(p.results))
		for i, result := range p.results {
			items[i] = Item(LineOf(
				Styled(fmt.Sprintf("%-9s", result.Get("kind").S()), dim()),
				Styled(truncate(result.Get("title").S(), sat(results.W-32)), bold()),
				Styled("  "+result.Get("tool_name").S(), dim())))
		}
		List{Items: items, Highlight: selected()}.Render(b, results, p.selected)
	case *NotificationsPopup:
		area := popupArea(b, "🔔 Notifications", 80, min(sat(screen.H-4), 30))
		if len(p.items) == 0 {
			b.RenderLine(StyledLine("Nothing here. All caught up ✨", dim()), area)
			return
		}
		width := sat(area.W - 4)
		items := make([]ListItem, len(p.items))
		for i, item := range p.items {
			items[i] = notificationItem(item, width)
		}
		List{Items: items, Highlight: selected()}.Render(b, area, p.selected)
	}
}

// notificationItem is a notification in a list: a dot when unread, and when it came.
func notificationItem(item api.Value, width int) ListItem {
	unread := !item.Get("read").Truthy()
	dot, style := Raw("  "), Style{}
	if unread {
		dot, style = Styled("● ", Style{}.Fg(accent())), bold()
	}
	return Item(
		LineOf(dot, Styled(truncate(item.Get("message").S(), width), style)),
		StyledLine("  "+ago(item.Get("created_at")), dim()))
}

// wrappedHeight is how many rows lines take when a Paragraph wraps them at width.
func wrappedHeight(lines []Line, width int) int {
	total := 0
	for _, line := range lines {
		total += len(wordWrap(line.graphemes(Style{}), max(width, 1), false))
	}
	return total
}

func popupArea(b *Buffer, title string, width, height int) Rect {
	return popup(b, title, width, height).Inner(1, 0)
}

// -- Building details -------------------------------------------------------------

// field adds "Label  value" to a detail, skipped when there's no value.
func field(lines *[]Line, label string, value string) {
	if value != "" {
		*lines = append(*lines, LineOf(Styled(fmt.Sprintf("%-10s", label), dim()), Raw(value)))
	}
}

func heading(lines *[]Line, text string) {
	*lines = append(*lines, RawLine(""), StyledLine(text, Style{}.Fg(accent()).With(Bold)))
}

func addText(lines *[]Line, text string, indent int) {
	for _, line := range splitLines(command.Clean(strings.TrimSpace(text))) {
		*lines = append(*lines, RawLine(strings.Repeat(" ", indent)+line))
	}
}

// comments adds the comments under a card or todo.
func comments(lines *[]Line, record api.Value) {
	all := record.Get("comments").Items()
	heading(lines, fmt.Sprintf("💬 Comments (%d)", len(all)))
	if len(all) == 0 {
		*lines = append(*lines, StyledLine("  No comments yet. Press c to write the first one.", dim()))
	}
	for _, comment := range all {
		author := command.Poster(comment, "Former member")
		*lines = append(*lines, RawLine(""), LineOf(
			Styled("  "+author, Style{}.Fg(personColor(author)).With(Bold)),
			Styled(" · "+ago(comment.Get("created_at")), dim())))
		addText(lines, comment.Get("body").S(), 2)
	}
}
