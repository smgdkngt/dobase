package events

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// server is a Dobase as far as a listener meets it: its MCP endpoint, with
// the tool event_list and the stream that says there is something new.
type server struct {
	*httptest.Server
	t *testing.T

	mu      sync.Mutex
	events  []int64
	newest  int64
	gapUpTo int64
	revoked bool
	down    bool
	noCable bool
	silent  bool
	asked   []string
	lines   []chan string
	opened  int
}

const token = "dobase_test_token"

func newServer(t *testing.T) *server {
	s := &server{t: t}
	mux := http.NewServeMux()
	mux.HandleFunc("/mcp", s.serveMCP)
	s.Server = httptest.NewServer(mux)
	t.Cleanup(func() {
		s.dropLines()
		s.Close()
	})
	return s
}

func (s *server) serveMCP(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	refused := s.revoked || r.Header.Get("Authorization") != "Bearer "+token
	s.mu.Unlock()
	if refused {
		w.WriteHeader(http.StatusUnauthorized)
		fmt.Fprint(w, `{"error":"invalid_token"}`)
		return
	}
	if r.Method == http.MethodGet {
		s.serveStream(w, r)
		return
	}

	body, _ := io.ReadAll(r.Body)
	message := api.MustParse(string(body))
	w.Header().Set("Content-Type", "application/json")
	switch message.Get("method").S() {
	case "initialize":
		w.Header().Set("Mcp-Session-Id", "session-1")
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18"}}`, message.Get("id").JSON())
	case "notifications/initialized":
		w.WriteHeader(http.StatusAccepted)
	case "tools/call":
		s.serveEvents(w, message)
	default:
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":{}}`, message.Get("id").JSON())
	}
}

func (s *server) serveEvents(w http.ResponseWriter, message api.Value) {
	s.mu.Lock()
	defer s.mu.Unlock()
	args := message.Get("params", "arguments")
	if name := message.Get("params", "name").S(); name != "event_list" {
		s.t.Errorf("called %s", name)
	}
	s.asked = append(s.asked, args.JSON())
	if s.down {
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprint(w, "<html>Bad gateway</html>")
		return
	}

	var listed []string
	if args.Has("after") || args.Has("since") {
		after := args.Get("after").Int()
		for _, id := range s.events {
			if id > after {
				listed = append(listed, fmt.Sprintf(`{"id":%d,"kind":"card.created","data":{"title":"Card %d\nwith <a> second line"}}`, id, id))
			}
		}
	}
	// Two to a page, so more than a page is met too
	more := len(listed) > 2
	cursor := s.newest
	if more {
		listed = listed[:2]
		cursor = api.MustParse(listed[1]).Get("id").Int()
	}
	gap := args.Has("after") && args.Get("after").Int() < s.gapUpTo
	page := fmt.Sprintf(`{"events":[%s],"cursor":%d,"more":%t,"gap":%t}`, strings.Join(listed, ","), cursor, more, gap)
	fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":{"content":[],"structuredContent":%s}}`, message.Get("id").JSON(), page)
}

// serveStream is the GET stream: pings, and a notification for every signalled event
func (s *server) serveStream(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	s.opened++
	if s.noCable {
		s.mu.Unlock()
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	silent := s.silent
	line := make(chan string, 16)
	s.lines = append(s.lines, line)
	s.mu.Unlock()

	w.Header().Set("Content-Type", "text/event-stream")
	w.WriteHeader(http.StatusOK)
	flusher := w.(http.Flusher)
	flusher.Flush()
	ping := time.NewTicker(10 * time.Millisecond)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case said, open := <-line:
			if !open {
				return
			}
			fmt.Fprint(w, said)
			flusher.Flush()
		case <-ping.C:
			// A stream that says nothing, and stays open: a connection that died on the way
			if !silent {
				fmt.Fprint(w, ": ping\n\n")
				flusher.Flush()
			}
		}
	}
}

// happen adds an event; with a signal, it is said on every line, as the server does.
func (s *server) happen(signal bool) int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.newest++
	s.events = append(s.events, s.newest)
	if signal {
		for _, line := range s.lines {
			line <- "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/resources/updated\",\"params\":{\"uri\":\"dobase://events\"}}\n\n"
		}
	}
	return s.newest
}

// elsewhere is an event in a tool that isn't this listener's: the number moves on, nothing is listed.
func (s *server) elsewhere() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.newest++
}

func (s *server) set(change func(*server)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	change(s)
}

func (s *server) dropLines() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, line := range s.lines {
		close(line)
	}
	s.lines = nil
}

func (s *server) open() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.lines)
}

func (s *server) questions() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.asked)
}

func (s *server) connections() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.opened
}

// output collects what a listener prints, line by line.
type output struct {
	mu    sync.Mutex
	lines []string
	fail  error
}

func (o *output) Write(data []byte) (int, error) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if o.fail != nil {
		return 0, o.fail
	}
	o.lines = append(o.lines, strings.TrimSuffix(string(data), "\n"))
	return len(data), nil
}

func (o *output) ids() string {
	o.mu.Lock()
	defer o.mu.Unlock()
	var ids []string
	for _, line := range o.lines {
		event, err := api.Parse([]byte(line))
		if err != nil || strings.Contains(line, "\n") {
			ids = append(ids, "broken:"+line)
		} else if event.Get("kind").S() == "stream.gap" {
			ids = append(ids, "gap")
		} else {
			ids = append(ids, event.Get("id").S())
		}
	}
	return strings.Join(ids, " ")
}

func listener(t *testing.T, s *server, out *output, name string) *Listener {
	t.Helper()
	server, err := api.NewMCP(s.URL, api.Static(token), "test")
	if err != nil {
		t.Fatal(err)
	}
	bookmark, err := OpenBookmark(name, s.URL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(bookmark.Close)
	line := &Line{Server: server, Quiet: 300 * time.Millisecond}
	return &Listener{Server: server, Out: out, Bookmark: bookmark, Line: line.Listen,
		Poll: time.Hour, Retry: 10 * time.Millisecond, RetryMax: 40 * time.Millisecond}
}

// follow runs a listener until the test ends or stop is called, which waits for it and gives how it ended.
func follow(t *testing.T, l *Listener) (stop func() error) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	ended := make(chan error, 1)
	go func() { ended <- l.Follow(ctx) }()
	var once sync.Once
	var result error
	stop = func() error {
		once.Do(func() {
			cancel()
			select {
			case result = <-ended:
			case <-time.After(5 * time.Second):
				t.Error("the listener didn't stop")
			}
		})
		return result
	}
	t.Cleanup(func() { stop() })
	return stop
}

func eventually(t *testing.T, what string, check func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !check() {
		if time.Now().After(deadline) {
			t.Fatalf("never happened: %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func state(t *testing.T) {
	t.Helper()
	t.Setenv("XDG_STATE_HOME", t.TempDir())
}

func TestAListenerStartsWhereTheStreamIsAndThenPrintsWhatHappensOnce(t *testing.T) {
	state(t)
	s := newServer(t)
	s.happen(false)
	s.happen(false)
	out := &output{}

	l := listener(t, s, out, "default")
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}
	if got := out.ids(); got != "" {
		t.Fatalf("a new listener printed what happened before it: %s", got)
	}

	s.happen(false)
	s.happen(false)
	s.happen(false)
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}
	if got := out.ids(); got != "3 4 5" {
		t.Fatalf("printed %s", got)
	}
	if err := l.Once(); err != nil || out.ids() != "3 4 5" {
		t.Fatalf("printed %s twice (%v)", out.ids(), err)
	}
}

func TestAListenerThatStartsAgainGoesOnWhereItWas(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	first := listener(t, s, out, "spark")
	if err := first.Once(); err != nil {
		t.Fatal(err)
	}
	s.happen(false)
	if err := first.Once(); err != nil {
		t.Fatal(err)
	}
	first.Bookmark.Close()

	s.happen(false)
	s.happen(false)
	second := listener(t, s, out, "spark")
	if err := second.Once(); err != nil {
		t.Fatal(err)
	}
	if got := out.ids(); got != "1 2 3" {
		t.Fatalf("printed %s", got)
	}
}

func TestAListenerStoppedHalfwayAPagePrintsTheRestNextTime(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	l := listener(t, s, out, "default")
	l.Once()
	s.happen(false)
	s.happen(false)

	// The reader went away after the first line
	out.lines, out.fail = nil, nil
	once := &failAfter{output: out, lines: 1}
	l.Out = once
	var gone *Gone
	if err := l.Once(); !errors.As(err, &gone) {
		t.Fatalf("ended with %v", err)
	}
	l.Bookmark.Close()

	again := listener(t, s, out, "default")
	if err := again.Once(); err != nil {
		t.Fatal(err)
	}
	if got := out.ids(); got != "1 2" {
		t.Fatalf("printed %s", got)
	}
}

type failAfter struct {
	*output
	lines int
}

func (f *failAfter) Write(data []byte) (int, error) {
	if f.lines == 0 {
		return 0, errors.New("broken pipe")
	}
	f.lines--
	return f.output.Write(data)
}

func TestEachEventIsOneLineWhateverItsTextSays(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	l := listener(t, s, out, "default")
	l.Once()
	s.happen(false)
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}

	if len(out.lines) != 1 || strings.ContainsAny(out.lines[0], "\n\r") {
		t.Fatalf("printed %q", out.lines)
	}
	if want := `{"id":1,"kind":"card.created","data":{"title":"Card 1\nwith <a> second line"}}`; out.lines[0] != want {
		t.Fatalf("printed %s", out.lines[0])
	}
}

func TestWhatWouldDoSomethingToATerminalIsSpelledOut(t *testing.T) {
	line := plain("{\"title\":\"a\u009b31mb\u202ec\u007fd é 🎉\"}")

	if want := `{"title":"a\u009b31mb\u202ec\u007fd é 🎉"}`; line != want {
		t.Fatalf("printed %q", line)
	}
	if value, err := api.Parse([]byte(line)); err != nil || value.Get("title").S() != "a\u009b31mb\u202ec\u007fd é 🎉" {
		t.Fatalf("no longer the same JSON: %v", err)
	}
}

func TestTheNumberMovesOnPastWhatIsNotForThisListener(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	l := listener(t, s, out, "default")
	l.Once()
	s.elsewhere()
	s.elsewhere()
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}

	if l.Bookmark.Cursor != 2 {
		t.Fatalf("bookmark at %d", l.Bookmark.Cursor)
	}
	contents, _ := os.ReadFile(filepath.Join(Dir(), "default.json"))
	if kept := api.MustParse(string(contents)); kept.Get("cursor").Int() != 2 || kept.Get("server").S() != s.URL {
		t.Fatalf("kept %s", contents)
	}
}

func TestSinceAndTheFiltersAreAskedOfTheServer(t *testing.T) {
	state(t)
	s := newServer(t)
	s.happen(false)
	out := &output{}
	l := listener(t, s, out, "default")
	l.Since = "2026-10-09T08:00:00Z"
	l.Filter = Filter{Tools: []string{"107", "110"}, Kinds: []string{"mail", "card.moved"}, SkipOwn: true}
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}
	s.happen(false)
	l.Once()

	want := []string{
		`{"kinds":["mail","card.moved"],"since":"2026-10-09T08:00:00Z","skip_own":true,"tool_ids":[107,110]}`,
		`{"after":1,"kinds":["mail","card.moved"],"skip_own":true,"tool_ids":[107,110]}`,
	}
	if got := strings.Join(s.asked, "\n"); got != strings.Join(want, "\n") {
		t.Fatalf("asked\n%s", got)
	}
	if got := out.ids(); got != "1 2" {
		t.Fatalf("printed %s", got)
	}
}

func TestAGapIsSaidAsALineOfItsOwn(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	l := listener(t, s, out, "default")
	l.Once()
	for range 4 {
		s.happen(false)
	}
	s.set(func(s *server) { s.gapUpTo = 2 })
	if err := l.Once(); err != nil {
		t.Fatal(err)
	}

	if got := out.ids(); got != "gap 1 2 3 4" {
		t.Fatalf("printed %s", got)
	}
	gap := api.MustParse(out.lines[0])
	if gap.Get("after").Int() != 0 || gap.Get("data", "reason").S() == "" {
		t.Fatalf("gap says %s", out.lines[0])
	}
}

func TestTwoListenersUnderOneNameAreRefusedAndUnderTwoNamesEachKeepTheirPlace(t *testing.T) {
	state(t)
	s := newServer(t)
	mac, spark := &output{}, &output{}
	first := listener(t, s, mac, "mac")
	second := listener(t, s, spark, "spark")
	first.Once()
	s.happen(false)
	second.Once()
	s.happen(false)
	first.Once()
	second.Once()

	if mac.ids() != "1 2" || spark.ids() != "2" {
		t.Fatalf("mac %s, spark %s", mac.ids(), spark.ids())
	}
	if _, err := OpenBookmark("mac", s.URL); err == nil || !strings.Contains(err.Error(), "is listening already") {
		t.Fatalf("a second listener called mac got %v", err)
	}
}

func TestABookmarkOfAnotherServerSaysNothingAboutThisOne(t *testing.T) {
	state(t)
	bookmark, err := OpenBookmark("default", "https://one.example.com")
	if err != nil {
		t.Fatal(err)
	}
	bookmark.Move(900)
	bookmark.Close()

	same, _ := OpenBookmark("default", "https://one.example.com")
	if !same.Known || same.Cursor != 900 {
		t.Fatalf("kept %+v", same)
	}
	same.Close()
	other, _ := OpenBookmark("default", "https://two.example.com")
	if other.Known {
		t.Fatalf("took over %+v", other)
	}
	other.Close()
}

func TestNamesThatAreNoFileNamesAreRefused(t *testing.T) {
	for name, valid := range map[string]bool{"default": true, "spark-1": true, "Mac_2.a": true, "": false, "../up": false, "a/b": false, ".hidden": false, "with space": false} {
		if ValidName(name) != valid {
			t.Errorf("%q valid: %t", name, !valid)
		}
	}
}

func TestFollowingPrintsAnEventTheMomentItIsSignalled(t *testing.T) {
	state(t)
	s := newServer(t)
	s.happen(false)
	out := &output{}
	follow(t, listener(t, s, out, "default"))
	eventually(t, "the line is open", func() bool { return s.open() == 1 })

	// Poll is an hour here: only the signal can have brought these
	s.happen(true)
	eventually(t, "the first event is printed", func() bool { return out.ids() == "2" })
	s.happen(true)
	s.happen(true)
	eventually(t, "the next two are printed", func() bool { return out.ids() == "2 3 4" })

}

func TestFollowingMissesNothingWhileTheLineIsDownAndPrintsNothingTwice(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	follow(t, listener(t, s, out, "default"))
	eventually(t, "the line is open", func() bool { return s.open() == 1 })
	s.happen(true)
	eventually(t, "the first event is printed", func() bool { return out.ids() == "1" })

	// The server goes away (a deploy), and things happen that nobody is told
	s.set(func(s *server) { s.noCable, s.down = true, true })
	s.dropLines()
	s.happen(false)
	s.happen(false)
	s.happen(false)
	time.Sleep(100 * time.Millisecond)
	if got := out.ids(); got != "1" {
		t.Fatalf("printed %s while the server was away", got)
	}

	s.set(func(s *server) { s.noCable, s.down = false, false })
	eventually(t, "what was missed is printed", func() bool { return out.ids() == "1 2 3 4" })
	eventually(t, "the line is open again", func() bool { return s.open() == 1 })
	s.happen(true)
	eventually(t, "and it goes on", func() bool { return out.ids() == "1 2 3 4 5" })
}

func TestAServerThatStaysAwayIsNotAskedMoreAndMoreOften(t *testing.T) {
	state(t)
	s := newServer(t)
	l := listener(t, s, &output{}, "default")
	follow(t, l)
	eventually(t, "the line is open", func() bool { return s.open() == 1 })

	s.set(func(s *server) { s.noCable, s.down = true, true })
	s.dropLines()
	time.Sleep(300 * time.Millisecond)
	early := s.questions()
	time.Sleep(600 * time.Millisecond)
	late := s.questions() - early

	// Asked again every 40 ms at most, and once for every time the line is tried
	// (every 40 to 60 ms): some 25 times in 600 ms, and no more as time goes by
	if late > 40 {
		t.Fatalf("asked %d times in 600 ms, after %d in the first 300", late, early)
	}
}

func TestALineThatGoesQuietIsMadeAgain(t *testing.T) {
	state(t)
	s := newServer(t)
	s.set(func(s *server) { s.silent = true })
	out := &output{}
	follow(t, listener(t, s, out, "default"))
	eventually(t, "the line is open", func() bool { return s.open() == 1 })

	// No ping for longer than the line may be quiet: it is dead, whatever the socket says
	s.set(func(s *server) { s.silent = false })
	s.happen(false)
	eventually(t, "a second line is made", func() bool { return s.connections() >= 2 })
	eventually(t, "and what happened meanwhile is printed", func() bool { return out.ids() == "1" })
}

func TestWithoutALineAskingEveryFewMinutesStillBringsEverything(t *testing.T) {
	state(t)
	s := newServer(t)
	s.set(func(s *server) { s.noCable = true })
	out := &output{}
	l := listener(t, s, out, "default")
	l.Poll = 20 * time.Millisecond
	follow(t, l)
	// A new listener starts where the stream is when it first asks
	eventually(t, "the listener has asked where the stream is", func() bool { return s.questions() >= 1 })

	s.happen(false)
	s.happen(false)
	eventually(t, "the events are printed", func() bool { return out.ids() == "1 2" })
}

func TestARevokedTokenEndsTheListenerWithAReason(t *testing.T) {
	state(t)
	s := newServer(t)
	out := &output{}
	l := listener(t, s, out, "default")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ended := make(chan error, 1)
	go func() { ended <- l.Follow(ctx) }()
	eventually(t, "the line is open", func() bool { return s.open() == 1 })

	// The server closes the stream and refuses the token from then on
	s.set(func(s *server) { s.revoked = true })
	s.dropLines()

	select {
	case err := <-ended:
		var gone *Gone
		if !errors.As(err, &gone) || !strings.Contains(err.Error(), "revoked") {
			t.Fatalf("ended with %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the listener went on with a revoked token")
	}
}

func TestAWrongTokenIsSaidBeforeAnythingElse(t *testing.T) {
	state(t)
	s := newServer(t)
	s.set(func(s *server) { s.revoked = true })
	l := listener(t, s, &output{}, "default")

	var gone *Gone
	if err := l.Follow(context.Background()); !errors.As(err, &gone) {
		t.Fatalf("ended with %v", err)
	}
	if s.connections() != 0 {
		t.Errorf("a line was tried with a token the server doesn't know")
	}
}

func TestStoppingAListenerEndsItWithoutAnError(t *testing.T) {
	state(t)
	s := newServer(t)
	stop := follow(t, listener(t, s, &output{}, "default"))
	eventually(t, "the line is open", func() bool { return s.open() == 1 })

	if err := stop(); err != nil {
		t.Fatalf("ended with %v", err)
	}
}

func TestWhyALineFailedNeverNamesTheToken(t *testing.T) {
	var said bytes.Buffer
	server, err := api.NewMCP("http://127.0.0.1:1", api.Static(token), "test")
	if err != nil {
		t.Fatal(err)
	}
	line := &Line{Server: server, Quiet: 200 * time.Millisecond}
	err = line.Listen(context.Background(), func() {})
	fmt.Fprintf(&said, "%v %+v %#v", err, err, err)

	if err == nil || strings.Contains(said.String(), token) {
		t.Fatalf("said %s", said.String())
	}
}
