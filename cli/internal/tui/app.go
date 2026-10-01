package tui

// The app's state, and how keys, jobs and drawing fit together.
//
// Screens never call the API from a key press directly: they queue a job, the
// loop draws a spinner, then runs it. So the screen always shows what's going on.

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Job is work that talks to the server, run by the loop after it has drawn a spinner.
type Job func(app *App) error

type Tone int

const (
	ToneInfo Tone = iota
	ToneSuccess
	ToneError
)

type toast struct {
	text string
	tone Tone
	at   time.Time
}

// undo is the last change you made, and how to take it back.
type undo struct {
	label string
	job   Job
	at    time.Time
}

// background refreshes live screens on another goroutine, so keys never wait for the server.
type background struct {
	client   api.API
	inflight *inflight
}

type liveResult struct {
	value api.Value
	err   error
}

type inflight struct {
	results chan liveResult
	started time.Time
	tool    int64
}

const undoFor = 60 * time.Second

type pending struct {
	label string
	job   Job
}

// Fx is what a key press asks the app to do.
type Fx struct {
	jobs       []pending
	popup      Popup
	closePopup bool
	toast      *toast
	openURL    *string
	openTool   *int64
	// openLink is a link into a tool: it opens the tool, then what the link points at.
	openLink *string
	back     bool
	confetti bool
}

// job queues job, with label next to the spinner while it runs.
func (fx *Fx) job(label string, job Job) {
	fx.jobs = append(fx.jobs, pending{label, job})
}

func (fx *Fx) say(text string, tone Tone) {
	fx.toast = &toast{text: text, tone: tone}
}

func ptr[T any](value T) *T { return &value }

// View is what screens may read from the app while drawing or handling a key.
type View struct {
	tools []api.Value
	tick  uint64
	me    api.Value
}

type App struct {
	api api.API
	// base is the server, e.g. https://app.dobase.co
	base   string
	me     api.Value
	tools  []api.Value
	screen Screen
	popup  Popup
	quit   bool
	tick   uint64
	// launchBrowser says whether `o` starts a browser; tests only record the URL.
	launchBrowser bool
	browser       func(url string) error
	opened        []string
	toast         *toast
	confetti      *Confetti
	jobs          []pending
	busy          string
	lastRefresh   time.Time
	// lastChange is when a job last changed something, so an older background refresh can't undo it on screen.
	lastChange time.Time
	undo       *undo
	background *background
	// pasting is on between the start and the end of pasted text; pastedBreak
	// says whether the last character of it was a line break.
	pasting, pastedBreak bool
}

func NewApp(server api.API, base string, browser func(string) error) *App {
	return &App{
		api:           server,
		base:          strings.TrimRight(base, "/"),
		screen:        &Home{},
		launchBrowser: true,
		browser:       browser,
		lastRefresh:   time.Now(),
		lastChange:    time.Now(),
	}
}

// refreshInBackground refreshes live screens in the background with this client.
func (a *App) refreshInBackground(client api.API) {
	a.background = &background{client: client}
}

// offerUndo lets `u` take back what was just done, for a minute.
func (a *App) offerUndo(label string, job Job) {
	a.undo = &undo{label: label, job: job, at: time.Now()}
}

// -- API ------------------------------------------------------------------------

func (a *App) get(path string, params ...api.Param) (api.Value, error) {
	return a.api.Request(api.Get, path, params, nil)
}

func (a *App) post(path string, body api.Value) (api.Value, error) {
	return a.api.Request(api.Post, path, nil, body)
}

func (a *App) patch(path string, body api.Value) (api.Value, error) {
	return a.api.Request(api.Patch, path, nil, body)
}

func (a *App) delete(path string) (api.Value, error) {
	return a.api.Request(api.Delete, path, nil, nil)
}

// Start loads who's signed in, their tools and the home screen.
func (a *App) Start() error {
	me, err := a.get("/profile")
	if err != nil {
		return err
	}
	a.me = me
	if err := a.loadTools(); err != nil {
		return err
	}
	home, err := loadHome(a)
	if err != nil {
		return err
	}
	a.screen = home
	return nil
}

func (a *App) loadTools() error {
	tools, err := a.get("/tools")
	if err != nil {
		return err
	}
	sorted := slices.Clone(tools.Items())
	slices.SortStableFunc(sorted, func(x, y api.Value) int {
		if c := strings.Compare(strings.ToLower(x.Get("name").S()), strings.ToLower(y.Get("name").S())); c != 0 {
			return c
		}
		return int(x.Get("id").Int() - y.Get("id").Int())
	})
	a.tools = sorted
	return nil
}

func (a *App) toolURL(tool api.Value) string {
	if url := tool.Get("url"); !url.IsNull() {
		return url.S()
	}
	return fmt.Sprintf("%s/tools/%s", a.base, tool.Get("id").S())
}

func (a *App) view() *View { return &View{tools: a.tools, tick: a.tick, me: a.me} }

// toolIndex is where the screen's tool is in the list, if it's there.
func (a *App) toolIndex() int {
	tool, ok := a.screen.Tool()
	if !ok {
		return -1
	}
	return slices.IndexFunc(a.tools, func(other api.Value) bool { return other.Get("id").Equal(tool.Get("id")) })
}

// -- Keys -----------------------------------------------------------------------

func (a *App) Key(key Key) {
	if key.Code == KeyRune && key.Ctrl && key.Rune == 'c' {
		a.quit = true
		return
	}
	fx := &Fx{}

	if a.popup != nil {
		popupKey(a.popup, key, fx)
		a.apply(fx)
		return
	}

	if !a.screen.Key(key, a.view(), fx) {
		a.globalKey(key, fx)
	}
	a.apply(fx)
}

// input is the text field being written in, if there is one.
func (a *App) input() *TextInput {
	switch popup := a.popup.(type) {
	case *InputPopup:
		return &popup.input
	case *SearchPopup:
		return &popup.input
	case nil:
		if chat, ok := a.screen.(*Chat); ok && chat.writing {
			return &chat.input
		}
	}
	return nil
}

// Paste takes in a character of pasted text. It goes into the field being
// written in, with a space for a tab or a run of line breaks, so a pasted
// line is never sent by itself. Without a field it goes nowhere: pasted text
// isn't keys to run.
func (a *App) Paste(char rune) {
	input := a.input()
	if input == nil {
		return
	}
	lineBreak := char == '\n' || char == '\r'
	if lineBreak && a.pastedBreak {
		return
	}
	a.pastedBreak = lineBreak
	if lineBreak || char == '\t' {
		char = ' '
	}
	input.Key(Key{Code: KeyRune, Rune: char})
}

func (a *App) globalKey(key Key, fx *Fx) {
	_, home := a.screen.(*Home)
	switch {
	case key.Is('q') && home:
		a.quit = true
	case key.Is('q', 'g') || key.Code == KeyEsc:
		fx.back = true
	case key.Is('?'):
		fx.popup = &HelpPopup{keys: a.screen.Help()}
	case key.Is('/'):
		fx.popup = &SearchPopup{}
	case key.Is('n'):
		fx.job("Fetching notifications", func(app *App) error {
			items, err := app.get("/notifications", api.Param{Name: "limit", Value: "30"})
			if err != nil {
				return err
			}
			app.popup = &NotificationsPopup{items: slices.Clone(items.Items())}
			return nil
		})
	case key.Is('r'):
		if job := a.screen.Refresh(); job != nil {
			fx.job("Refreshing", job)
		} else {
			fx.job("Refreshing", func(app *App) error {
				if err := app.loadTools(); err != nil {
					return err
				}
				selected := 0
				if home, ok := app.screen.(*Home); ok {
					selected = home.selected
				}
				home, err := loadHome(app)
				if err != nil {
					return err
				}
				home.selected = min(selected, sat(len(app.tools)-1))
				app.screen = home
				return nil
			})
		}
	case key.Is(']', '['):
		if len(a.tools) > 0 {
			current, count := a.toolIndex(), len(a.tools)
			forward := key.Is(']')
			var next int
			switch {
			case current < 0 && forward:
				next = 0
			case current < 0:
				next = count - 1
			case forward:
				next = (current + 1) % count
			default:
				next = (current + count - 1) % count
			}
			fx.openTool = ptr(a.tools[next].Get("id").Int())
		}
	case key.Is('u'):
		taken := a.undo
		a.undo = nil
		if taken != nil && time.Since(taken.at) < undoFor {
			fx.job("Undoing "+taken.label, func(app *App) error {
				if err := taken.job(app); err != nil {
					return err
				}
				app.say("Undone ↩", ToneInfo)
				return nil
			})
		} else {
			fx.say("Nothing to undo", ToneInfo)
		}
	case key.Is('o'):
		if tool, ok := a.screen.Tool(); ok {
			fx.openURL = ptr(a.toolURL(tool))
		} else {
			fx.openURL = ptr(a.base)
		}
	}
}

func (a *App) apply(fx *Fx) {
	if fx.closePopup {
		a.popup = nil
	}
	if fx.popup != nil {
		a.popup = fx.popup
	}
	if fx.toast != nil {
		a.say(fx.toast.text, fx.toast.tone)
	}
	if fx.openURL != nil {
		a.openURL(*fx.openURL)
	}
	if fx.confetti {
		a.celebrate()
	}
	if fx.back {
		a.goHome()
	}
	if fx.openTool != nil {
		a.openTool(*fx.openTool)
	}
	if fx.openLink != nil {
		a.openLink(*fx.openLink)
	}
	a.jobs = append(a.jobs, fx.jobs...)
}

// say shows a toast.
func (a *App) say(text string, tone Tone) {
	a.toast = &toast{text: text, tone: tone, at: time.Now()}
}

func (a *App) celebrate() {
	a.tick++
	a.confetti = newConfetti(0x9e37_79b9_7f4a_7c15 ^ (a.tick * 2_654_435_761))
	a.say(cheers[(a.tick*7)%uint64(len(cheers))], ToneSuccess)
}

func (a *App) goHome() {
	if _, home := a.screen.(*Home); home {
		return
	}
	selected := max(a.toolIndex(), 0)
	a.jobs = append(a.jobs, pending{"Going home", func(app *App) error {
		home, err := loadHome(app)
		if err != nil {
			return err
		}
		home.selected = selected
		app.screen = home
		return nil
	}})
}

func (a *App) openTool(id int64) {
	index := slices.IndexFunc(a.tools, func(tool api.Value) bool { return tool.Get("id").Int() == id })
	if index < 0 {
		a.say("That tool isn't in your list any more.", ToneError)
		return
	}
	tool := a.tools[index]
	a.jobs = append(a.jobs, pending{"Opening " + tool.Get("name").S(), func(app *App) error {
		screen, err := openScreen(app, tool)
		if err != nil {
			return err
		}
		app.screen = screen
		app.lastRefresh = time.Now()
		return nil
	}})
}

// openLink opens the tool a Dobase link is in, then the card, todo or document it points at.
func (a *App) openLink(url string) {
	id, ok := toolIDIn(url)
	if !ok {
		a.openURL(url)
		return
	}
	a.openTool(id)
	a.jobs = append(a.jobs, pending{"Opening it", func(app *App) error { return focus(app, url) }})
}

// openURL opens url in the installed app or the browser; a path is on this server.
func (a *App) openURL(url string) {
	if strings.HasPrefix(url, "/") {
		url = a.base + url
	}
	a.opened = append(a.opened, url)
	if !a.launchBrowser {
		return
	}
	if err := a.browser(url); err != nil {
		a.say("Couldn't open it. The link: "+url, ToneError)
		return
	}
	a.say("Opened it", ToneInfo)
}

// -- The loop -------------------------------------------------------------------

// hasJob says whether a job is waiting; its label goes by the spinner for the next draw.
func (a *App) hasJob() bool {
	a.busy = ""
	if len(a.jobs) > 0 {
		a.busy = a.jobs[0].label
	}
	return len(a.jobs) > 0
}

// runJob runs the first queued job; its error, if any, becomes a toast.
func (a *App) runJob() {
	if len(a.jobs) == 0 {
		return
	}
	next := a.jobs[0]
	a.jobs = a.jobs[1:]
	err := next.job(a)
	a.busy = ""
	a.lastChange = time.Now()
	if err != nil {
		a.say(err.Error(), ToneError)
	}
}

// settle runs every queued job, for tests.
func (a *App) settle() {
	for len(a.jobs) > 0 {
		a.runJob()
	}
}

// onTick is called a few times a second: animations, and a quiet refresh of live screens.
func (a *App) onTick() {
	a.tick++
	if a.confetti != nil && a.confetti.finished() {
		a.confetti = nil
	}
	if a.toast != nil && time.Since(a.toast.at) > 4*time.Second {
		a.toast = nil
	}
	a.pollBackground()
}

func (a *App) screenTool() int64 {
	if tool, ok := a.screen.Tool(); ok {
		return tool.Get("id").Int()
	}
	return 0
}

// pollBackground picks up a finished background refresh, and starts the next one every ten seconds.
func (a *App) pollBackground() {
	bg := a.background
	if bg == nil {
		return
	}
	tool := a.screenTool()

	if bg.inflight != nil {
		select {
		case result := <-bg.inflight.results:
			if result.err == nil && bg.inflight.tool == tool && bg.inflight.started.After(a.lastChange) {
				a.screen.ApplyLive(result.value)
			}
		default:
			return
		}
		bg.inflight = nil
	}

	if time.Since(a.lastRefresh) < 10*time.Second || len(a.jobs) > 0 {
		return
	}
	a.lastRefresh = time.Now()
	path, params, ok := a.screen.LiveRequest()
	if !ok {
		return
	}
	results := make(chan liveResult, 1)
	client := bg.client
	go func() {
		value, err := client.Request(api.Get, path, params, nil)
		results <- liveResult{value, err}
	}()
	bg.inflight = &inflight{results: results, started: time.Now(), tool: tool}
}

// -- Drawing --------------------------------------------------------------------

var spinner = [10]string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

func (a *App) Draw(b *Buffer) {
	area := b.Area
	if area.W < 50 || area.H < 14 {
		Paragraph{Lines: []Line{RawLine("Make the window a little bigger 🙂")}, Style: dim()}.Render(b, area)
		return
	}

	parts := splitVertical(area, Length(1), Min(1), Length(1))
	header, body, footer := parts[0], parts[1], parts[2]
	a.drawHeader(b, header)
	a.screen.Draw(b, body, a.view())
	a.drawFooter(b, footer)

	if a.popup != nil {
		drawPopup(a.popup, b)
	}
	if a.confetti != nil {
		a.confetti.Render(b, body)
	}
}

func (a *App) drawHeader(b *Buffer, area Rect) {
	left := []Span{Styled(" dobase ", Style{}.Fg(accent()).With(Bold))}
	if tool, ok := a.screen.Tool(); ok {
		left = append(left,
			Styled("› ", dim()),
			Raw(toolIcon(tool.Get("type").S())+" "),
			Styled(tool.Get("name").S(), bold()))
	}
	host := a.base
	if _, rest, found := strings.Cut(a.base, "://"); found {
		host, _, _ = strings.Cut(rest, "://")
	}
	right := LineOf(Raw(a.me.Get("name").S()), Styled(" · "+host+" ", dim())).RightAligned()
	b.RenderLine(LineOf(left...), area)
	b.RenderLine(right, area)
}

func (a *App) drawFooter(b *Buffer, area Rect) {
	var hints []hint
	if a.popup != nil {
		hints = popupHints(a.popup)
	} else {
		hints = a.screen.Hints()
	}
	if a.popup == nil && a.undo != nil && time.Since(a.undo.at) < undoFor {
		hints = append([]hint{{"u", "undo"}}, hints...)
	}
	hints = append(hints, hint{"?", "help"})
	line := hintsLine(hints)
	line.Spans = append([]Span{Raw(" ")}, line.Spans...)
	b.RenderLine(line, area)

	var status *Line
	if a.busy != "" {
		frame := spinner[a.tick%10]
		status = ptr(LineOf(Styled(frame+" ", Style{}.Fg(accent())), Raw(a.busy+"… ")))
	} else if a.toast != nil {
		color := accent()
		switch a.toast.tone {
		case ToneSuccess:
			color = success()
		case ToneError:
			color = danger()
		}
		text := truncate(a.toast.text, area.W*2/3)
		status = ptr(LineOf(Styled(" "+text+" ", Style{}.Fg(color).With(Bold))))
	}
	if status != nil {
		// The last cell stays empty: writing there makes some terminals scroll the whole screen.
		width := min(status.Width(), sat(area.W-1))
		spot := Rect{sat(area.Right() - (width + 1)), area.Y, width, area.H}
		b.Clear(spot)
		b.RenderLine(*status, spot)
	}
}
