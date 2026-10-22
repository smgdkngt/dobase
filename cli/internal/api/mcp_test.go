package api

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// mcpServer answers tools/call with whatever result the test gives it, and
// forgets its session or refuses a token when asked to.
type mcpServer struct {
	mu        sync.Mutex
	sessions  int
	session   string
	forget    bool
	refuse    string
	result    string
	calls     []string
	userAgent string
}

func (s *mcpServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.refuse != "" && r.Header.Get("Authorization") == "Bearer "+s.refuse {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	body, _ := io.ReadAll(r.Body)
	message := MustParse(string(body))
	w.Header().Set("Content-Type", "application/json")
	switch message.Get("method").S() {
	case "initialize":
		s.sessions++
		s.session = fmt.Sprintf("session-%d", s.sessions)
		s.userAgent = r.Header.Get("User-Agent")
		w.Header().Set("Mcp-Session-Id", s.session)
		fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":{}}`, message.Get("id").JSON())
		return
	case "notifications/initialized":
		w.WriteHeader(http.StatusAccepted)
		return
	}
	if s.forget || r.Header.Get("Mcp-Session-Id") != s.session {
		s.forget = false
		s.session = ""
		w.WriteHeader(http.StatusNotFound)
		return
	}
	s.calls = append(s.calls, message.Get("params", "name").S()+" "+message.Get("params", "arguments").JSON())
	fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":%s}`, message.Get("id").JSON(), s.result)
}

func newMCPServer(t *testing.T, s *mcpServer, creds Credentials) *MCP {
	t.Helper()
	server := httptest.NewServer(s)
	t.Cleanup(server.Close)
	client, err := NewMCP(server.URL, creds, "dobase/test")
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestACallGivesBackTheAPIsOwnJSON(t *testing.T) {
	s := &mcpServer{}
	client := newMCPServer(t, s, Static("token"))

	s.result = `{"content":[],"structuredContent":{"z":1,"a":2}}`
	if got, err := client.Call("card_show", map[string]any{"tool_id": 13}); err != nil || got.JSON() != `{"z":1,"a":2}` {
		t.Fatalf("got %s, %v", got.JSON(), err)
	}
	s.result = `{"content":[],"structuredContent":{"items":[1,2]},"_meta":{"dobase/shape":"items"}}`
	if got, _ := client.Call("tool_list", nil); got.JSON() != `[1,2]` {
		t.Fatalf("got %s", got.JSON())
	}
	s.result = `{"content":[],"structuredContent":{"done":true},"_meta":{"dobase/shape":"nothing"}}`
	if got, _ := client.Call("card_delete", nil); !got.IsNull() {
		t.Fatalf("got %s", got.JSON())
	}
	if want := `card_show {"tool_id":13}`; s.calls[0] != want {
		t.Errorf("called %s", s.calls[0])
	}
}

func TestAToolErrorReadsAsTheAPIsOwnError(t *testing.T) {
	s := &mcpServer{}
	client := newMCPServer(t, s, Static("token"))

	s.result = `{"content":[{"type":"text","text":"Not found, or not shared with you."}],"isError":true,"_meta":{"dobase/status":404,"dobase/message":"Card not found"}}`
	_, err := client.Call("card_show", nil)
	if err == nil || err.Error() != "Card not found (HTTP 404)" || StatusOf(err) != 404 {
		t.Fatalf("got %v", err)
	}
	s.result = `{"content":[{"type":"text","text":"Nothing to change"}],"isError":true}`
	if _, err := client.Call("card_update", nil); err == nil || err.Error() != "Nothing to change" {
		t.Fatalf("got %v", err)
	}
}

func TestASessionTheServerForgotIsStartedAgain(t *testing.T) {
	s := &mcpServer{result: `{"structuredContent":{}}`}
	client := newMCPServer(t, s, Static("token"))
	client.Call("whoami", nil)
	s.mu.Lock()
	s.forget = true
	s.mu.Unlock()
	if _, err := client.Call("whoami", nil); err != nil {
		t.Fatal(err)
	}
	if s.sessions != 2 || len(s.calls) != 2 {
		t.Fatalf("%d sessions, calls %v", s.sessions, s.calls)
	}
	if !strings.HasPrefix(s.userAgent, "Go-http-client") && s.userAgent != "dobase/test" {
		t.Errorf("user agent %q", s.userAgent)
	}
}

// refreshing gives out "old" until the server refuses it, then "new"
type refreshing struct{ refreshed int }

func (r *refreshing) Token() (string, error) {
	if r.refreshed > 0 {
		return "new", nil
	}
	return "old", nil
}

func (r *refreshing) Refresh(refused string) (string, error) {
	if refused != "old" {
		return "", Failf("refused %s", refused)
	}
	r.refreshed++
	return "new", nil
}

func TestARefusedTokenIsRefreshedOnceAndTheCallMadeAgain(t *testing.T) {
	s := &mcpServer{result: `{"structuredContent":{"ok":true}}`}
	creds := &refreshing{}
	client := newMCPServer(t, s, creds)
	s.refuse = "old"
	got, err := client.Call("whoami", nil)
	if err != nil || got.JSON() != `{"ok":true}` || creds.refreshed != 1 {
		t.Fatalf("got %s, %v, refreshed %d", got.JSON(), err, creds.refreshed)
	}
}

func TestAPersonalTokenThatIsRefusedSaysSoWithItsStatus(t *testing.T) {
	s := &mcpServer{refuse: "token"}
	client := newMCPServer(t, s, Static("token"))
	_, err := client.Call("whoami", nil)
	if StatusOf(err) != http.StatusUnauthorized || !strings.Contains(err.Error(), "dobase login") {
		t.Fatalf("got %v", err)
	}
}
