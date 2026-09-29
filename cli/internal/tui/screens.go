package tui

// One screen per kind of tool, plus home. Each screen draws itself, handles
// its own keys (returning false for keys the app should handle) and knows how
// to reload its data without losing your place.

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

type Screen interface {
	// Tool is the tool on screen; home has none.
	Tool() (api.Value, bool)
	Draw(b *Buffer, area Rect, view *View)
	// Key returns false when the key is left to the app.
	Key(key Key, view *View, fx *Fx) bool
	// Refresh reloads the screen's data, keeping the selection; nil when there's nothing to reload.
	Refresh() Job
	// LiveRequest is what a screen that changes while you look at it reloads every few seconds, in the background.
	LiveRequest() (path string, params []api.Param, ok bool)
	// ApplyLive takes in what LiveRequest fetched, keeping your place.
	ApplyLive(value api.Value)
	Hints() []hint
	// Help is the keys of this screen, for the help popup.
	Help() []hint
}

// notLive is for screens that don't refresh by themselves.
type notLive struct{}

func (notLive) LiveRequest() (string, []api.Param, bool) { return "", nil, false }
func (notLive) ApplyLive(api.Value)                      {}

// openScreen loads the screen for tool.
func openScreen(app *App, tool api.Value) (Screen, error) {
	switch tool.Get("type").S() {
	case "boards":
		return loadBoard(app, tool)
	case "todos":
		return loadTodos(app, tool)
	case "chat":
		return loadChat(app, tool)
	case "docs":
		return loadDocs(app, tool)
	case "calendar":
		return loadCalendar(app, tool)
	case "files":
		return loadFiles(app, tool, 0)
	case "mail":
		return loadMail(app, tool, 0)
	}
	return &Room{tool: tool}, nil
}

// focus shows what a link points at after its tool opened from it (a search
// result, a notification): a card, todo, document, folder or conversation.
func focus(app *App, url string) error {
	current, ok := app.screen.Tool()
	if !ok {
		return nil
	}
	tool := current.Get("id").Int()
	numberAfter := func(marker string) (int64, bool) {
		_, rest, found := strings.Cut(url, marker)
		if !found {
			return 0, false
		}
		end := strings.IndexFunc(rest, func(r rune) bool { return r < '0' || r > '9' })
		if end >= 0 {
			rest = rest[:end]
		}
		number, err := strconv.ParseInt(rest, 10, 64)
		return number, err == nil
	}

	if card, ok := numberAfter("card="); ok {
		if board, ok := app.screen.(*Board); ok {
			board.selectCard(card)
		}
		detail, err := cardDetail(app, tool, card)
		if err != nil {
			return err
		}
		app.popup = detail
	} else if item, ok := numberAfter("item="); ok {
		if todos, ok := app.screen.(*Todos); ok {
			todos.selectItem(item)
		}
		detail, err := todoDetail(app, tool, item)
		if err != nil {
			return err
		}
		app.popup = detail
	} else if document, ok := numberAfter("/documents/"); ok {
		content, err := app.get(fmt.Sprintf("/tools/%d/docs/documents/%d", tool, document))
		if err != nil {
			return err
		}
		if docs, ok := app.screen.(*Docs); ok {
			docs.show(content)
		}
	} else if folder, ok := numberAfter("folder_id="); ok {
		if _, ok := app.screen.(*Files); ok {
			files, err := loadFiles(app, current, folder)
			if err != nil {
				return err
			}
			app.screen = files
		}
	} else if conversation, ok := numberAfter("/mails/"); ok {
		detail, err := conversationDetail(app, tool, conversation)
		if err != nil {
			return err
		}
		app.popup = detail
	}
	return nil
}

// moveSelection moves a selection up or down a list of count items; true when the key was a move.
func moveSelection(selected *int, count int, key Key) bool {
	last := sat(count - 1)
	switch {
	case key.Code == KeyDown || key.Is('j'):
		*selected = min(*selected+1, last)
	case key.Code == KeyUp || key.Is('k'):
		*selected = sat(*selected - 1)
	case key.Code == KeyPageDown:
		*selected = min(*selected+10, last)
	case key.Code == KeyPageUp:
		*selected = sat(*selected - 10)
	case key.Code == KeyHome:
		*selected = 0
	case key.Code == KeyEnd || key.Is('G'):
		*selected = last
	default:
		return false
	}
	return true
}

// toolPath is /tools/ID for tool.
func toolPath(tool api.Value) string { return "/tools/" + tool.Get("id").S() }
