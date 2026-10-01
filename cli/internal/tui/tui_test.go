package tui

// The app against a fake server, drawn on a simulated terminal and driven by key presses.

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

type call struct {
	method api.Method
	path   string
	body   api.Value
	// query is the query string: "limit=60&before=12".
	query string
}

// fakeServer answers from a map of paths (and records every request). A
// request whose key is in failing gets an error instead.
type fakeServer struct {
	responses api.Value
	calls     *[]call
	failing   map[string]bool
}

func (f *fakeServer) Request(method api.Method, path string, params []api.Param, body any) (api.Value, error) {
	query := make([]string, len(params))
	for i, param := range params {
		query[i] = param.Name + "=" + param.Value
	}
	*f.calls = append(*f.calls, call{method, path, api.Of(body), strings.Join(query, "&")})
	key := path
	if method != api.Get {
		key = string(method[0]) + strings.ToLower(string(method[1:])) + " " + path
	}
	if f.failing[key] {
		return api.Null, api.Failf("The server is having a moment (HTTP 500)")
	}
	if response := f.responses.Get(key); f.responses.Has(key) {
		return response, nil
	}
	return api.Object(), nil
}

func (f *fakeServer) Upload(string, []api.FilePart, []api.Param) (api.Value, error) {
	panic("unreachable")
}

// Download saves ten bytes, whatever the file.
func (f *fakeServer) Download(path, destination string) (string, error) {
	*f.calls = append(*f.calls, call{method: api.Get, path: path})
	return "", os.WriteFile(destination, []byte("ten bytes!"), 0o644)
}

func card(id int, title string) string {
	return fmt.Sprintf(`{ "id": %d, "title": %q, "color": "", "comments_count": 0, "attachments_count": 0 }`, id, title)
}

func server() api.Value {
	return api.MustParse(`{
		"/profile": { "id": 1, "name": "Sem Goedknegt", "email_address": "sem@example.com" },
		"/tools": [
			{ "id": 10, "name": "Launch", "type": "boards", "unread": true },
			{ "id": 11, "name": "Chores", "type": "todos" },
			{ "id": 12, "name": "Team", "type": "chat" }
		],
		"/notifications": [
			{ "id": 5, "read": false, "message": "Ann commented on Fix login", "url": "/tools/10/board?card=101", "created_at": "2026-09-24T10:00:00Z" }
		],
		"/tools/10/board": { "columns": [
			{ "id": 1, "name": "To Do", "cards": [` + card(101, "Fix login") + `, ` + card(102, "Write post") + `] },
			{ "id": 2, "name": "Done", "cards": [] }
		] },
		"/tools/10/board/cards/101": { "id": 101, "title": "Fix login", "description": "Safari logs people out.",
			"column": { "name": "To Do" }, "comments": [{ "user": { "name": "Ann" }, "body": "Found it!", "created_at": "2026-09-24T10:00:00Z" }],
			"attachments": [] },
		"/tools/11/todo": { "lists": [{ "id": 7, "title": "Home", "items": [{ "id": 70, "title": "Water plants", "completed": false }] }] },
		"/tools/12/chat": { "messages": [
			{ "id": 1, "user": { "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z", "reactions": [] }
		] },
		"/search": { "results": [{ "kind": "card", "title": "Fix login", "tool_name": "Launch", "url": "http://localhost/tools/10/board?card=101" }] },
		"Post /columns/1/cards": { "id": 103, "title": "Ship it" }
	}`)
}

type harness struct {
	t      *testing.T
	app    *App
	screen tcell.SimulationScreen
	calls  *[]call
	server *fakeServer
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	calls := &[]call{}
	fake := &fakeServer{responses: server(), calls: calls, failing: map[string]bool{}}
	app := NewApp(fake, "http://localhost", nil)
	app.launchBrowser = false
	if err := app.Start(); err != nil {
		t.Fatal(err)
	}
	screen := tcell.NewSimulationScreen("UTF-8")
	if err := screen.Init(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(screen.Fini)
	screen.SetSize(100, 30)
	return &harness{t: t, app: app, screen: screen, calls: calls, server: fake}
}

// answer makes the server answer key ("/path", or "Post /path") with this JSON from now on.
func (h *harness) answer(key, response string) *harness {
	h.server.responses = h.server.responses.With(key, api.MustParse(response))
	return h
}

// fail makes requests to key fail, or work again.
func (h *harness) fail(key string, failing bool) *harness {
	h.server.failing[key] = failing
	return h
}

func (h *harness) press(key Key) *harness {
	h.app.Key(key)
	h.app.settle()
	return h
}

func (h *harness) char(char rune) *harness    { return h.press(Key{Code: KeyRune, Rune: char}) }
func (h *harness) code(code KeyCode) *harness { return h.press(Key{Code: code}) }

func (h *harness) typing(text string) *harness {
	for _, char := range text {
		h.char(char)
	}
	return h
}

// text draws the app and reads the screen back, row by row.
func (h *harness) text() string {
	show(h.screen, h.app)
	width, height := h.screen.Size()
	rows := make([]string, height)
	for y := range height {
		var row strings.Builder
		for x := 0; x < width; {
			symbol, _, cells := h.screen.Get(x, y)
			row.WriteString(symbol)
			x += max(cells, 1)
		}
		rows[y] = row.String()
	}
	return strings.Join(rows, "\n")
}

// sent is the body of the last request with this method and path.
func (h *harness) sent(method api.Method, path string) (api.Value, bool) {
	for i := len(*h.calls) - 1; i >= 0; i-- {
		if c := (*h.calls)[i]; c.method == method && c.path == path {
			return c.body, true
		}
	}
	return api.Null, false
}

func (h *harness) expectSent(method api.Method, path, want string) {
	h.t.Helper()
	got, ok := h.sent(method, path)
	if !ok {
		h.t.Fatalf("no %s %s sent; calls: %v", method, path, *h.calls)
	}
	var gotAny, wantAny any
	_ = json.Unmarshal([]byte(got.JSON()), &gotAny)
	_ = json.Unmarshal([]byte(want), &wantAny)
	if !reflect.DeepEqual(gotAny, wantAny) {
		h.t.Fatalf("%s %s sent %s, want %s", method, path, got.JSON(), want)
	}
}

func expectContains(t *testing.T, screen string, texts ...string) {
	t.Helper()
	for _, text := range texts {
		if !strings.Contains(screen, text) {
			t.Fatalf("the screen doesn't show %q:\n%s", text, screen)
		}
	}
}

func TestHomeGreetsAndListsTheTools(t *testing.T) {
	screen := newHarness(t).text()
	expectContains(t, screen, "Sem", "Launch", "Chores", "Team", "Ann commented on Fix login", "1 new notification")
}

func TestABoardShowsColumnsAndOpensACard(t *testing.T) {
	h := newHarness(t)
	h.char('2')
	expectContains(t, h.text(), "To Do 2", "Done 0", "Write post")

	h.code(KeyEnter)
	expectContains(t, h.text(), "Safari logs people out.", "Found it!")
}

func TestMovingACardToDoneSavesItAndCelebrates(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('L')
	h.expectSent(api.Patch, "/tools/10/board/cards/101/position", `{ "column_id": 2 }`)
}

func TestANewCardGoesToTheSelectedColumn(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('c').typing("Ship it").code(KeyEnter)
	h.expectSent(api.Post, "/columns/1/cards", `{ "card": { "title": "Ship it" } }`)
}

func TestSpaceTicksATodoOff(t *testing.T) {
	h := newHarness(t)
	h.char('1').char(' ')
	if _, ok := h.sent(api.Post, "/tools/11/todo/items/70/completion"); !ok {
		t.Fatal("the todo wasn't ticked off")
	}
}

func TestAChatMessageIsSentAsAParagraph(t *testing.T) {
	h := newHarness(t)
	h.char('3')
	expectContains(t, h.text(), "Morning!")

	h.char('i').typing("Hi <all>").code(KeyEnter)
	h.expectSent(api.Post, "/tools/12/chat/messages", `{ "message": { "body": "<p>Hi &lt;all&gt;</p>" } }`)
}

func TestKeysTypedWhileWritingAreTextNotCommands(t *testing.T) {
	h := newHarness(t)
	h.char('3').char('i').typing("q/?n")

	if h.app.quit {
		t.Fatal("q quit while writing")
	}
	if h.app.popup != nil {
		t.Fatal("a popup opened while writing")
	}
	expectContains(t, h.text(), "q/?n")
}

func TestASearchResultOpensTheCardItFound(t *testing.T) {
	h := newHarness(t)
	h.char('/').typing("login").code(KeyEnter)
	expectContains(t, h.text(), "Fix login")

	h.code(KeyEnter)
	screen := h.text()
	if first, _, _ := strings.Cut(screen, "\n"); !strings.Contains(first, "Launch") {
		t.Fatalf("the board didn't open:\n%s", screen)
	}
	expectContains(t, screen, "Safari logs people out.")
}

func TestEscapeGoesHomeAndQQuits(t *testing.T) {
	h := newHarness(t)
	h.char('2').code(KeyEsc)
	expectContains(t, h.text(), "Your tools")

	h.char('q')
	if !h.app.quit {
		t.Fatal("q didn't quit")
	}
}

func TestOOpensTheCardInTheBrowser(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('o')

	if want := []string{"http://localhost/tools/10/board?card=101"}; !reflect.DeepEqual(h.app.opened, want) {
		t.Fatalf("opened %v, want %v", h.app.opened, want)
	}
}

func TestATinyTerminalAsksForRoom(t *testing.T) {
	h := newHarness(t)
	h.screen.SetSize(40, 10)
	expectContains(t, h.text(), "bigger")
}

func TestUUndoesAMove(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('L')
	expectContains(t, h.text(), "u undo")

	h.char('u')
	h.expectSent(api.Patch, "/tools/10/board/cards/101/position", `{ "column_id": 1, "position": 0 }`)
	if screen := h.text(); strings.Contains(screen, "u undo") {
		t.Fatalf("undo is still offered:\n%s", screen)
	}
}

func TestERenamesACardStartingFromItsTitle(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('e')
	expectContains(t, h.text(), "Fix login")

	h.code(KeyBackspace).typing("ns").code(KeyEnter)
	h.expectSent(api.Patch, "/tools/10/board/cards/101", `{ "card": { "title": "Fix logins" } }`)
}

func TestDSetsADueDateInWords(t *testing.T) {
	h := newHarness(t)
	h.char('2').char('d').typing("tomorrow").code(KeyEnter)

	tomorrow := command.Today().AddDate(0, 0, 1).Format(command.DateLayout)
	h.expectSent(api.Patch, "/tools/10/board/cards/101", `{ "card": { "due_date": "`+tomorrow+`" } }`)
}

func TestDueDatesReadLikePeopleWriteThem(t *testing.T) {
	today := command.Today()
	check := func(text string, want *time.Time) {
		t.Helper()
		got, err := dueDate(text)
		if err != nil || (got == nil) != (want == nil) || (got != nil && !got.Equal(*want)) {
			t.Fatalf("dueDate(%q) = %v, %v; want %v", text, got, err, want)
		}
	}

	check("none", nil)
	check("+3", ptr(today.AddDate(0, 0, 3)))
	check("2026-10-01", ptr(time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)))
	friday, err := dueDate("fri")
	if err != nil || friday == nil {
		t.Fatalf("fri: %v", err)
	}
	if friday.Weekday() != time.Friday || !friday.After(today) || friday.After(today.AddDate(0, 0, 7)) {
		t.Fatalf("fri is %v", friday)
	}
	if _, err := dueDate("someday"); err == nil {
		t.Fatal("someday is a date")
	}
}

func TestARefreshKeepsTheSelectedCardWhenCardsMove(t *testing.T) {
	h := newHarness(t)
	h.char('2').code(KeyDown)
	board, ok := h.app.screen.(*Board)
	if !ok {
		t.Fatal("not on the board")
	}

	// Someone else put a card above it.
	board.replace([]api.Value{
		api.MustParse(`{ "id": 1, "name": "To Do", "cards": [` + card(100, "New one") + `, ` + card(101, "Fix login") + `, ` + card(102, "Write post") + `] }`),
		api.MustParse(`{ "id": 2, "name": "Done", "cards": [] }`),
	}, 0)
	h.code(KeyEnter)
	if _, ok := h.sent(api.Get, "/tools/10/board/cards/102"); !ok {
		t.Fatalf("the wrong card opened: %v", *h.calls)
	}
}

func TestNewChatMessagesJoinTheOnesAlreadyLoaded(t *testing.T) {
	h := newHarness(t)
	h.char('3')
	chat, ok := h.app.screen.(*Chat)
	if !ok {
		t.Fatal("not in the chat")
	}

	chat.merge(api.MustParse(`{ "messages": [
		{ "id": 1, "user": { "name": "Ann" }, "body": "Morning!", "created_at": "2026-09-24T08:00:00Z", "reactions": [] },
		{ "id": 2, "user": { "name": "Bo" }, "body": "Hey Ann", "created_at": "2026-09-24T08:01:00Z", "reactions": [] }
	] }`))
	expectContains(t, h.text(), "Morning!", "Hey Ann")
}

func TestOpeningANotificationMarksItRead(t *testing.T) {
	h := newHarness(t)
	h.code(KeyTab).code(KeyEnter)

	if _, ok := h.sent(api.Post, "/notifications/5/read"); !ok {
		t.Fatal("the notification wasn't marked read")
	}
	expectContains(t, h.text(), "Safari logs people out.")
}
