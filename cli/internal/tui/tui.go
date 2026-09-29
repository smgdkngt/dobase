// Package tui is `dobase` without arguments in a terminal: a full-screen app
// to look around your tools, move cards, tick off todos and chat.
package tui

import (
	"fmt"
	"os"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// Run opens the app until it's quit.
func Run(cfg *config.Config, userAgent string) error {
	url := cfg.URL()
	client, err := api.NewClient(url, cfg.Token(), userAgent)
	if err != nil {
		return err
	}
	app := NewApp(client, url, func(link string) error { return command.Open(url, link) })
	app.refreshInBackground(client)
	fmt.Fprint(os.Stderr, "Loading your workspace…")
	err = app.Start()
	fmt.Fprint(os.Stderr, "\r\x1b[2K")
	if err != nil {
		return err
	}

	screen, err := tcell.NewScreen()
	if err == nil {
		err = screen.Init()
	}
	if err != nil {
		return api.Failf("Can't start the app in this terminal: %v", err)
	}
	// The terminal comes back as it was, also when something panics.
	defer func() {
		if recovered := recover(); recovered != nil {
			screen.Fini()
			panic(recovered)
		}
	}()
	loop(screen, app)
	screen.Fini()
	return nil
}

func loop(screen tcell.Screen, app *App) {
	events := make(chan tcell.Event, 16)
	quit := make(chan struct{})
	defer close(quit)
	go screen.ChannelEvents(events, quit)

	for !app.quit {
		job := app.hasJob()
		show(screen, app)

		// A queued job runs after the spinner is on screen.
		if job {
			app.runJob()
			continue
		}

		select {
		case event := <-events:
			switch event := event.(type) {
			case *tcell.EventKey:
				if key, ok := keyFrom(event); ok {
					app.Key(key)
				}
			case *tcell.EventResize:
				screen.Sync()
			}
		case <-time.After(100 * time.Millisecond):
		}
		app.onTick()
	}
}

// show draws a frame of the app and puts it on screen.
func show(screen tcell.Screen, app *App) {
	width, height := screen.Size()
	buffer := NewBuffer(width, height)
	app.Draw(buffer)
	flush(buffer, screen)
	screen.Show()
}

// flush copies the buffer to the screen. The last cell stays empty: writing
// there makes some terminals scroll the whole screen.
func flush(buffer *Buffer, screen tcell.Screen) {
	area := buffer.Area
	for y := 0; y < area.H; y++ {
		for x := 0; x < area.W; {
			c := buffer.at(x, y)
			width := max(textWidth(c.symbol), 1)
			if y == area.H-1 && x+width >= area.W {
				screen.Put(x, y, " ", tcell.StyleDefault)
				break
			}
			screen.Put(x, y, c.symbol, styleOf(c))
			x += width
		}
	}
	if buffer.cursor != nil {
		screen.ShowCursor(buffer.cursor[0], buffer.cursor[1])
	} else {
		screen.HideCursor()
	}
}

func styleOf(c *cell) tcell.Style {
	style := tcell.StyleDefault.Foreground(c.fg).Background(c.bg)
	style = style.Bold(c.mod&Bold != 0).Italic(c.mod&Italic != 0).Reverse(c.mod&Reversed != 0).StrikeThrough(c.mod&CrossedOut != 0)
	if c.mod&Underlined != 0 {
		style = style.Underline(true)
	}
	return style
}

// keyFrom turns a tcell key event into a Key.
func keyFrom(event *tcell.EventKey) (Key, bool) {
	ctrl := event.Modifiers()&tcell.ModCtrl != 0
	switch event.Key() {
	case tcell.KeyRune:
		return Key{Code: KeyRune, Rune: event.Rune(), Ctrl: ctrl}, true
	case tcell.KeyEnter:
		return Key{Code: KeyEnter}, true
	case tcell.KeyEsc:
		return Key{Code: KeyEsc}, true
	case tcell.KeyTab:
		return Key{Code: KeyTab}, true
	case tcell.KeyBacktab:
		return Key{Code: KeyBackTab}, true
	case tcell.KeyBackspace, tcell.KeyBackspace2:
		return Key{Code: KeyBackspace}, true
	case tcell.KeyDelete:
		return Key{Code: KeyDelete}, true
	case tcell.KeyLeft:
		return Key{Code: KeyLeft}, true
	case tcell.KeyRight:
		return Key{Code: KeyRight}, true
	case tcell.KeyUp:
		return Key{Code: KeyUp}, true
	case tcell.KeyDown:
		return Key{Code: KeyDown}, true
	case tcell.KeyHome:
		return Key{Code: KeyHome}, true
	case tcell.KeyEnd:
		return Key{Code: KeyEnd}, true
	case tcell.KeyPgUp:
		return Key{Code: KeyPageUp}, true
	case tcell.KeyPgDn:
		return Key{Code: KeyPageDown}, true
	}
	if event.Key() >= tcell.KeyCtrlA && event.Key() <= tcell.KeyCtrlZ {
		return Key{Code: KeyRune, Rune: rune(event.Key()-tcell.KeyCtrlA) + 'a', Ctrl: true}, true
	}
	return Key{}, false
}
