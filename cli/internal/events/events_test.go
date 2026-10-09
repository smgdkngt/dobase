package events

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/net/websocket"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// server is a Dobase as far as a listener meets it: GET /events and the cable.
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
	lines   []*websocket.Conn
	origins []string
}

const token = "dobase_test_token"

func newServer(t *testing.T) *server {
	s := &server{t: t}
	mux := http.NewServeMux()
	mux.HandleFunc("/events", s.serveEvents)
	mux.Handle("/cable", websocket.Server{Handshake: s.handshake, Handler: s.serveCable})
	s.Server = httptest.NewServer(mux)
	t.Cleanup(s.Close)
	return s
}

func (s *server) serveEvents(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.asked = append(s.asked, r.URL.RawQuery)
	w.Header().Set("Content-Type", "application/json")
	switch {
	case s.down:
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprint(w, "<html>Bad gateway</html>")
		return
	case s.revoked || r.Header.Get("Authorization") != "Bearer "+token:
		w.WriteHeader(http.StatusUnauthorized)
		fmt.Fprint(w, `{"error":"Invalid access token"}`)
		return
	}

	query := r.URL.Query()
	var listed []string
	if query.Has("after") || query.Has("since") {
		after, _ := strconv.ParseInt(query.Get("after"), 10, 64)
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
	after, _ := strconv.ParseInt(query.Get("after"), 10, 64)
	gap := query.Has("after") && after < s.gapUpTo
	fmt.Fprintf(w, `{"events":[%s],"cursor":%d,"more":%t,"gap":%t}`, strings.Join(listed, ","), cursor, more, gap)
}

func (s *server) handshake(config *websocket.Config, r *http.Request) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.origins = append(s.origins, r.Header.Get("Origin"))
	if s.noCable || r.Header.Get("Authorization") != "Bearer "+token || r.Header.Get("Origin") != "http://"+r.Host {
		return errors.New("refused")
	}
	return nil
}

func (s *server) serveCable(ws *websocket.Conn) {
	s.mu.Lock()
	silent, revoked := s.silent, s.revoked
	s.mu.Unlock()
	if revoked {
		websocket.Message.Send(ws, `{"type":"disconnect","reason":"unauthorized","reconnect":false}`)
		return
	}
	websocket.Message.Send(ws, `{"type":"welcome"}`)
	var command string
	if err := websocket.Message.Receive(ws, &command); err != nil {
		return
	}
	if got := api.MustParse(command); got.Get("command").S() != "subscribe" || got.Get("identifier").S() != `{"channel":"EventsChannel"}` {
		s.t.Errorf("subscribed with %s", command)
	}
	websocket.Message.Send(ws, `{"identifier":"{\"channel\":\"EventsChannel\"}","type":"confirm_subscription"}`)
	s.mu.Lock()
	s.lines = append(s.lines, ws)
	s.mu.Unlock()
	for !silent {
		if err := websocket.Message.Send(ws, `{"type":"ping","message":1}`); err != nil {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	// A line that says nothing, and stays open: a connection that died on the way
	var nothing string
	websocket.Message.Receive(ws, &nothing)
}

// happen adds an event; with a signal, it is said on every line, as the server does.
func (s *server) happen(signal bool) int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.newest++
	s.events = append(s.events, s.newest)
	if signal {
		for _, line := range s.lines {
			websocket.Message.Send(line, fmt.Sprintf(`{"identifier":"{\"channel\":\"EventsChannel\"}","message":{"id":%d}}`, s.newest))
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
		line.Close()
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
	return len(s.origins)
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
	client, err := api.NewClient(s.URL, token, "test")
	if err != nil {
		t.Fatal(err)
	}
	bookmark, err := OpenBookmark(name, s.URL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(bookmark.Close)
	line := &Line{Server: s.URL, Token: token, UserAgent: "test", Quiet: 300 * time.Millisecond}
	return &Listener{Server: client, Out: out, Bookmark: bookmark, Line: line.Listen,
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
		"since=2026-10-09T08%3A00%3A00Z&tool%5B%5D=107&tool%5B%5D=110&kind%5B%5D=mail&kind%5B%5D=card.moved&skip_own=1",
		"after=1&tool%5B%5D=107&tool%5B%5D=110&kind%5B%5D=mail&kind%5B%5D=card.moved&skip_own=1",
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

	s.set(func(s *server) {
		if s.origins[0] != s.URL {
			t.Errorf("connected with Origin %q, the server is %s", s.origins[0], s.URL)
		}
	})
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

	// The server closes the line and refuses the token from then on
	s.set(func(s *server) {
		s.revoked = true
		for _, line := range s.lines {
			websocket.Message.Send(line, `{"type":"disconnect","reason":"unauthorized","reconnect":false}`)
			line.Close()
		}
	})

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
	line := &Line{Server: "http://127.0.0.1:1", Token: token, UserAgent: "test", Quiet: 200 * time.Millisecond}
	err := line.Listen(context.Background(), func() {})
	fmt.Fprintf(&said, "%v %+v %#v", err, err, err)

	if err == nil || strings.Contains(said.String(), token) {
		t.Fatalf("said %s", said.String())
	}
}

func TestTheCableIsFoundBesideTheServerAndOnlyOverHTTP(t *testing.T) {
	for server, want := range map[string]string{
		"https://app.dobase.co":       "wss://app.dobase.co/cable https://app.dobase.co",
		"https://app.dobase.co/":      "wss://app.dobase.co/cable https://app.dobase.co",
		"http://localhost:3010":       "ws://localhost:3010/cable http://localhost:3010",
		"https://example.com/dobase/": "wss://example.com/dobase/cable https://example.com",
	} {
		config, err := (&Line{Server: server, Token: token}).config()
		if err != nil {
			t.Fatal(err)
		}
		if got := config.Location.String() + " " + config.Origin.String(); got != want {
			t.Errorf("%s: %s", server, got)
		}
		if config.Header.Get("Authorization") != "Bearer "+token {
			t.Errorf("%s: no token", server)
		}
	}
	if _, err := (&Line{Server: "ftp://example.com"}).config(); err == nil {
		t.Error("ftp is no server")
	}
}
