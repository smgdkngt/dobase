package tui

// A chat: messages by day, refreshed every few seconds, and a line to write in.

import (
	"fmt"
	"math"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var chatHelp = []hint{
	{"i / enter", "Write a message"},
	{"enter", "Send it (while writing)"},
	{"esc", "Stop writing; again to go home"},
	{"↑ ↓ / j k", "Scroll"},
	{"end / G", "Jump to the newest message"},
	{"home", "Jump to the oldest loaded; again for older ones"},
	{"+", "Put a 👍 on the newest message"},
	{"u", "Undo: unsend your message, or take the 👍 back"},
	{"o", "Open the chat in your browser"},
	{"r", "Reload (it also reloads by itself)"},
}

// chatPage is how many messages a chat loads at a time.
const chatPage = 60

type Chat struct {
	tool     api.Value
	messages []api.Value
	// hasMore says whether the server has older messages than the first one here.
	hasMore      bool
	loadingOlder bool
	input        TextInput
	writing      bool
	// scroll is lines scrolled up from the newest message.
	scroll int
	// unseen is messages that came in while you were scrolled up.
	unseen int
	// width and height are the size last drawn at, to keep your place when messages come in.
	width, height int
}

func loadChat(app *App, tool api.Value) (*Chat, error) {
	chat, err := fetchChat(app, tool, 0)
	if err != nil {
		return nil, err
	}
	return &Chat{
		tool:     tool,
		messages: slices.Clone(chat.Get("messages").Items()),
		hasMore:  chat.Get("has_more").Truthy(),
		width:    80,
		height:   20,
	}, nil
}

func (s *Chat) Tool() (api.Value, bool) { return s.tool, true }
func (s *Chat) Help() []hint            { return chatHelp }

func (s *Chat) Hints() []hint {
	if s.writing {
		return []hint{{"enter", "send"}, {"esc", "stop writing"}}
	}
	return []hint{{"i", "write"}, {"↑↓", "scroll"}, {"+", "👍 newest"}, {"esc", "home"}}
}

func (s *Chat) Refresh() Job { return reloadChat }

func (s *Chat) LiveRequest() (string, []api.Param, bool) {
	return toolPath(s.tool) + "/chat", []api.Param{{Name: "limit", Value: strconv.Itoa(chatPage)}}, true
}

func (s *Chat) ApplyLive(value api.Value) { s.merge(value) }

// merge takes in the newest messages, keeping older ones already loaded, what
// you're writing, and the spot you scrolled to.
func (s *Chat) merge(chat api.Value) {
	fresh := chat.Get("messages").Items()
	if len(fresh) == 0 {
		return
	}
	first := fresh[0].Get("id").Int()
	known := map[int64]bool{}
	for _, message := range s.messages {
		known[message.Get("id").Int()] = true
	}
	arrived := 0
	for _, message := range fresh {
		if !known[message.Get("id").Int()] {
			arrived++
		}
	}
	before := len(s.lines(s.width))

	var messages []api.Value
	for _, message := range s.messages {
		if message.Get("id").Int() < first {
			messages = append(messages, message)
		}
	}
	if len(messages) == 0 {
		s.hasMore = chat.Get("has_more").Truthy()
	}
	s.messages = append(messages, fresh...)

	if s.scroll > 0 {
		s.scroll += sat(len(s.lines(s.width)) - before)
		s.unseen += arrived
	}
}

func (s *Chat) top() int { return sat(len(s.lines(s.width)) - s.height) }

func (s *Chat) scrollUp(lines int, fx *Fx) {
	top := s.top()
	if s.scroll >= top && s.hasMore && !s.loadingOlder {
		s.loadingOlder = true
		tool := s.tool
		var before int64
		if len(s.messages) > 0 {
			before = s.messages[0].Get("id").Int()
		}
		fx.job("Loading older messages", func(app *App) error {
			older, err := fetchChat(app, tool, before)
			if err != nil {
				return err
			}
			if chat, ok := app.screen.(*Chat); ok {
				chat.messages = append(slices.Clone(older.Get("messages").Items()), chat.messages...)
				chat.hasMore = older.Get("has_more").Truthy()
				chat.loadingOlder = false
			}
			return nil
		})
	}
	s.scroll = min(s.scroll+lines, max(top, s.scroll))
}

func (s *Chat) scrollDown(lines int) {
	s.scroll = sat(s.scroll - lines)
	if s.scroll == 0 {
		s.unseen = 0
	}
}

func (s *Chat) Key(key Key, view *View, fx *Fx) bool {
	if s.writing {
		switch key.Code {
		case KeyEsc:
			s.writing = false
		case KeyEnter:
			if !s.input.IsBlank() {
				text := strings.TrimSpace(s.input.Text())
				s.input.Clear()
				s.scrollDown(math.MaxInt)
				tool := s.tool.Get("id").Int()
				fx.job("Sending", func(app *App) error {
					message, err := app.post(fmt.Sprintf("/tools/%d/chat/messages", tool), api.Object("message", api.Object("body", command.Paragraphs(text))))
					if err != nil {
						return err
					}
					if err := reloadChat(app); err != nil {
						return err
					}
					id := message.Get("id").Int()
					app.offerUndo("the message", func(app *App) error {
						if _, err := app.delete(fmt.Sprintf("/tools/%d/chat/messages/%d", tool, id)); err != nil {
							return err
						}
						return reloadChat(app)
					})
					return nil
				})
			}
		default:
			s.input.Key(key)
		}
		return true
	}

	switch {
	case key.Is('i', 'c') || key.Code == KeyEnter:
		s.writing = true
	case key.Code == KeyUp || key.Is('k'):
		s.scrollUp(1, fx)
	case key.Code == KeyDown || key.Is('j'):
		s.scrollDown(1)
	case key.Code == KeyPageUp:
		s.scrollUp(max(s.height-2, 1), fx)
	case key.Code == KeyPageDown || key.Is(' '):
		s.scrollDown(max(s.height-2, 1))
	case key.Code == KeyHome:
		s.scrollUp(math.MaxInt/2, fx)
	case key.Code == KeyEnd || key.Is('G'):
		s.scrollDown(math.MaxInt)
	case key.Is('+'):
		if len(s.messages) > 0 {
			message := s.messages[len(s.messages)-1]
			tool, id := s.tool.Get("id").Int(), message.Get("id").Int()
			author := message.Get("user", "name").Or("someone")
			path := fmt.Sprintf("/tools/%d/chat/messages/%d/reactions", tool, id)
			fx.job("Reacting", func(app *App) error {
				if _, err := app.post(path, api.Object("emoji", "👍")); err != nil {
					return err
				}
				if err := reloadChat(app); err != nil {
					return err
				}
				app.say("👍 for "+author, ToneSuccess)
				app.offerUndo("the 👍", func(app *App) error {
					if _, err := app.delete(path + "/" + url.QueryEscape("👍")); err != nil {
						return err
					}
					return reloadChat(app)
				})
				return nil
			})
		}
	default:
		return false
	}
	return true
}

func (s *Chat) Draw(b *Buffer, area Rect, view *View) {
	parts := splitVertical(area, Min(3), Length(3))
	messagesArea, inputArea := parts[0], parts[1]
	block := panel(toolIcon("chat")+" "+s.tool.Get("name").S(), !s.writing)
	inner := block.Inner(messagesArea)
	block.Render(b, messagesArea)

	s.width = sat(inner.W - 2)
	s.height = inner.H
	lines := s.lines(s.width)
	if len(lines) == 0 {
		Paragraph{Lines: []Line{RawLine("It's quiet in here. Press i and say hi 👋")}, Style: dim()}.Render(b, inner)
	} else {
		height := inner.H
		s.scroll = min(s.scroll, sat(len(lines)-height))
		end := len(lines) - s.scroll
		start := sat(end - height)
		visible := lines[start:end]
		// Keep the newest message at the bottom, like a chat does.
		pad := sat(height - len(visible))
		spot := Rect{inner.X, inner.Y + pad, inner.W, inner.H - pad}
		Paragraph{Lines: visible}.Render(b, spot.Inner(1, 0))
		if s.scroll > 0 {
			var text string
			switch s.unseen {
			case 0:
				text = " ↓ newer below · G to jump "
			case 1:
				text = " ↓ 1 new message · G to jump "
			default:
				text = fmt.Sprintf(" ↓ %d new messages · G to jump ", s.unseen)
			}
			note := LineOf(Styled(text, Style{}.Fg(accent()).With(Bold))).RightAligned()
			b.RenderLine(note, Rect{messagesArea.X, messagesArea.Bottom() - 1, messagesArea.W, 1})
		}
		if start == 0 && len(lines) > height {
			top := " the beginning of this chat 🌱 "
			if s.loadingOlder {
				top = " ↑ loading older messages… "
			} else if s.hasMore {
				top = " ↑ scroll up for older messages "
			}
			b.RenderLine(StyledLine(top, dim()).Centered(), Rect{messagesArea.X, messagesArea.Y, messagesArea.W, 1})
		}
	}

	title, placeholder := "Press i to write", ""
	if s.writing {
		title, placeholder = "Message · enter to send", "Say something nice…"
	}
	inputBlock := panel(title, s.writing)
	field := inputBlock.Inner(inputArea)
	inputBlock.Render(b, inputArea)
	field = Rect{field.X + 1, field.Y, sat(field.W - 2), field.H}
	s.input.Render(b, field, placeholder, s.writing)
}

// lines are every message as lines, oldest first, with a divider for each day.
func (s *Chat) lines(width int) []Line {
	var lines []Line
	var day time.Time
	var previousAuthor string
	var previousAt time.Time
	hasPrevious := false
	today := civil(time.Now())
	for _, message := range s.messages {
		created, ok := local(message.Get("created_at"))
		if !ok {
			continue
		}
		if !civil(created).Equal(day) {
			day = civil(created)
			hasPrevious = false
			label := created.Format("Monday 2 January")
			if day.Equal(today) {
				label = "Today"
			}
			rule := strings.Repeat("─", sat(width-(len([]rune(label))+2))/2)
			lines = append(lines, RawLine(""), StyledLine(rule+" "+label+" "+rule, dim()).Centered())
		}

		// A name heads each run of messages by one person, and again after a pause.
		author := message.Get("user", "name").Or("Former member")
		continues := hasPrevious && previousAuthor == author && created.Sub(previousAt) < 5*time.Minute
		if !continues {
			edited := ""
			if message.Get("edited_at").Truthy() {
				edited = " (edited)"
			}
			lines = append(lines, RawLine(""), LineOf(
				Styled(author, Style{}.Fg(personColor(author)).With(Bold)),
				Styled(" "+created.Format("15:04")+edited, dim())))
		}
		previousAuthor, previousAt, hasPrevious = author, created, true
		if message.Get("reply_to").Truthy() {
			reply := "↳ " + message.Get("reply_to", "user_name").S() + ": " + message.Get("reply_to", "preview").S()
			lines = append(lines, StyledLine(truncate(reply, width), dim().With(Italic)))
		}
		for _, line := range wrap(command.Clean(strings.TrimSpace(message.Get("body").S())), width) {
			lines = append(lines, RawLine(line))
		}
		for _, file := range message.Get("files").Items() {
			lines = append(lines, StyledLine(fmt.Sprintf("📎 %s (%s)", file.Get("filename").S(), command.Bytes(file.Get("byte_size"))), dim()))
		}
		var reactions []string
		for _, reaction := range message.Get("reactions").Items() {
			reactions = append(reactions, fmt.Sprintf("%s %d", reaction.Get("emoji").S(), len(reaction.Get("users").Items())))
		}
		if len(reactions) > 0 {
			lines = append(lines, StyledLine(strings.Join(reactions, "  "), Style{}.Fg(warning())))
		}
	}
	return lines
}

// fetchChat is the newest page of messages, or the page before message before (when not 0).
func fetchChat(app *App, tool api.Value, before int64) (api.Value, error) {
	params := []api.Param{{Name: "limit", Value: strconv.Itoa(chatPage)}}
	if before != 0 {
		params = append(params, api.Param{Name: "before", Value: strconv.FormatInt(before, 10)})
	}
	return app.get(toolPath(tool)+"/chat", params...)
}

func reloadChat(app *App) error {
	chat, ok := app.screen.(*Chat)
	if !ok {
		return nil
	}
	fresh, err := fetchChat(app, chat.tool, 0)
	if err != nil {
		return err
	}
	if chat, ok := app.screen.(*Chat); ok {
		chat.merge(fresh)
	}
	return nil
}
