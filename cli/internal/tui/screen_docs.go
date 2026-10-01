package tui

// Docs: the documents on the left, the one you open on the right.

import (
	"fmt"
	"slices"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var docsHints = []hint{{"↑↓", "choose"}, {"enter", "read"}, {"tab", "switch pane"}, {"o", "browser"}, {"esc", "home"}}

var docsHelp = []hint{
	{"↑ ↓ / j k", "Choose a document, or scroll it"},
	{"enter", "Read the document"},
	{"tab", "Switch between the list and the document"},
	{"o", "Open the document in your browser to edit it"},
	{"r", "Reload"},
	{"esc", "Back to the list, then home"},
}

type Docs struct {
	notLive
	tool      api.Value
	documents []api.Value
	selected  int
	open      *api.Value
	reading   bool
	scroll    int
}

func loadDocs(app *App, tool api.Value) (*Docs, error) {
	docs, err := app.get(toolPath(tool) + "/docs")
	if err != nil {
		return nil, err
	}
	return &Docs{tool: tool, documents: slices.Clone(docs.Get("documents").Items())}, nil
}

func (s *Docs) Tool() (api.Value, bool) { return s.tool, true }
func (s *Docs) Hints() []hint           { return docsHints }
func (s *Docs) Help() []hint            { return docsHelp }

// show shows document on the right, selecting it in the list.
func (s *Docs) show(document api.Value) {
	if position := slices.IndexFunc(s.documents, func(other api.Value) bool { return other.Get("id").Equal(document.Get("id")) }); position >= 0 {
		s.selected = position
	}
	s.open = &document
	s.reading = true
	s.scroll = 0
}

func (s *Docs) Refresh() Job {
	tool, selected := s.tool, s.selected
	var open int64
	hasOpen := s.open != nil
	if hasOpen {
		open = s.open.Get("id").Int()
	}
	return func(app *App) error {
		fresh, err := loadDocs(app, tool)
		if err != nil {
			return err
		}
		fresh.selected = min(selected, sat(len(fresh.documents)-1))
		if hasOpen {
			document, err := app.get(fmt.Sprintf("%s/docs/documents/%d", toolPath(tool), open))
			if err != nil {
				return err
			}
			fresh.open = &document
		}
		if docs, ok := app.screen.(*Docs); ok {
			fresh.reading = docs.reading
			fresh.scroll = docs.scroll
			app.screen = fresh
		}
		return nil
	}
}

func (s *Docs) Key(key Key, view *View, fx *Fx) bool {
	switch {
	case key.OneOf(KeyTab, KeyBackTab):
		s.reading = !s.reading && s.open != nil
	case key.Code == KeyEsc && s.reading:
		s.reading = false
	case (key.Code == KeyEnter || key.Code == KeyRight || key.Is('l')) && !s.reading:
		if s.selected >= len(s.documents) {
			return true
		}
		tool, id := s.tool.Get("id").S(), s.documents[s.selected].Get("id").S()
		fx.job("Opening the document", func(app *App) error {
			document, err := app.get("/tools/" + tool + "/docs/documents/" + id)
			if err != nil {
				return err
			}
			if docs, ok := app.screen.(*Docs); ok {
				docs.show(document)
			}
			return nil
		})
	case (key.Code == KeyLeft || key.Is('h')) && s.reading:
		s.reading = false
	case (key.Code == KeyDown || key.Is('j')) && s.reading:
		s.scroll++
	case (key.Code == KeyUp || key.Is('k')) && s.reading:
		s.scroll = sat(s.scroll - 1)
	case (key.Code == KeyPageDown || key.Is(' ')) && s.reading:
		s.scroll += 15
	case key.Code == KeyPageUp && s.reading:
		s.scroll = sat(s.scroll - 15)
	case key.Is('o'):
		var document *api.Value
		if s.reading {
			document = s.open
		} else if s.selected < len(s.documents) {
			document = &s.documents[s.selected]
		}
		if document == nil {
			return false
		}
		fx.openURL = ptr(fmt.Sprintf("/tools/%s/docs/documents/%s", s.tool.Get("id").S(), document.Get("id").S()))
	case !s.reading:
		return moveSelection(&s.selected, len(s.documents), key)
	default:
		return false
	}
	return true
}

func (s *Docs) Draw(b *Buffer, area Rect, view *View) {
	listArea, pageArea := splitPercentages(area, 32)

	width := sat(listArea.W - 4)
	block := panel(toolIcon("docs")+" "+s.tool.Get("name").S(), !s.reading)
	if len(s.documents) == 0 {
		Paragraph{Lines: []Line{RawLine("No documents yet.")}, Style: dim(), Block: block}.Render(b, listArea)
	} else {
		items := make([]ListItem, len(s.documents))
		for i, document := range s.documents {
			editing := ""
			if document.Get("locked").Truthy() {
				editing = " ✎ " + document.Get("locked_by", "name").S()
			}
			items[i] = Item(
				StyledLine(truncate(document.Get("title").S(), width), bold()),
				StyledLine(ago(document.Get("updated_at"))+editing, dim()))
		}
		List{Items: items, Block: block, Highlight: selected()}.Render(b, listArea, s.selected)
	}

	if s.open == nil {
		Paragraph{Lines: []Line{RawLine(""), StyledLine("Press enter to read a document 📖", dim()).Centered()}, Block: panel("📖", false)}.Render(b, pageArea)
		return
	}
	document := *s.open
	lines := []Line{
		StyledLine(fmt.Sprintf("Edited %s by %s", ago(document.Get("updated_at")), document.Get("updated_by", "name").S()), dim()),
		RawLine(""),
	}
	content := document.Get("content").S()
	if strings.TrimSpace(content) == "" {
		lines = append(lines, StyledLine("(empty)", dim()))
	}
	for _, line := range splitLines(command.Clean(content)) {
		lines = append(lines, RawLine(line))
	}
	frame := panel(document.Get("title").S(), s.reading)
	// Scrolling stops with the last line in view.
	page := frame.Inner(pageArea)
	s.scroll = min(s.scroll, sat(wrappedHeight(lines, page.W, false)-page.H))
	Paragraph{Lines: lines, Wrap: true, Block: frame, Scroll: s.scroll}.Render(b, pageArea)
}
