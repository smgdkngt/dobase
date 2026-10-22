package api

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
)

// Protocol is the MCP version the CLI speaks.
const Protocol = "2025-06-18"

// Credentials give the token to send, and a new one when the server refused it:
// a login by OAuth has tokens that last an hour. A personal token is what it is.
type Credentials interface {
	Token() (string, error)
	// Refresh is given the token the server refused and returns the one to try instead.
	Refresh(refused string) (string, error)
}

// Static is a token that never changes: a personal access token.
type Static string

func (s Static) Token() (string, error) { return string(s), nil }

func (s Static) Refresh(string) (string, error) {
	return "", &Error{Kind: Failed, Message: "The server refused the token. Run `dobase login URL` again, or set DOBASE_TOKEN.", Status: http.StatusUnauthorized}
}

// MCP talks to a Dobase server's /mcp: its tools by name, and its stream of
// what changed. A tool answers with the API's own JSON, so what the CLI
// prints is the same as it was over the plain API.
//
// A session starts on the first call and is started again when the server
// forgot it, which a deploy does.
type MCP struct {
	client *Client

	mu      sync.Mutex
	session string
	id      int
}

// NewMCP talks to serverURL with the token creds give.
func NewMCP(serverURL string, creds Credentials, userAgent string) (*MCP, error) {
	client, err := NewClient(serverURL, creds, userAgent)
	if err != nil {
		return nil, err
	}
	return &MCP{client: client}, nil
}

// Client is the plain HTTP side, for files: uploads and downloads stay requests of their own.
func (m *MCP) Client() *Client { return m.client }

func (m *MCP) Upload(path string, files []FilePart, fields []Param) (Value, error) {
	return m.client.Upload(path, files, fields)
}

func (m *MCP) Download(path, destination string) (string, error) {
	return m.client.Download(path, destination)
}

// Call runs a tool and gives back the API's JSON: an object, a list, or null for nothing.
func (m *MCP) Call(tool string, args map[string]any) (Value, error) {
	if args == nil {
		args = map[string]any{}
	}
	result, err := m.request("tools/call", map[string]any{"name": tool, "arguments": args})
	if err != nil {
		return Null, err
	}
	meta := result.Get("_meta")
	if result.Get("isError").Truthy() {
		if status := meta.Get("dobase/status").Int(); status > 0 {
			return Null, &Error{Kind: Failed, Message: fmt.Sprintf("%s (HTTP %d)", meta.Get("dobase/message").S(), status), Status: int(status)}
		}
		return Null, Failf("%s", result.Get("content").Items()[0].Get("text").S())
	}
	content := result.Get("structuredContent")
	switch meta.Get("dobase/shape").S() {
	case "items":
		return content.Get("items"), nil
	case "nothing":
		return Null, nil
	case "result":
		return content.Get("result"), nil
	}
	return content, nil
}

// request sends one JSON-RPC request in the session and returns its result.
func (m *MCP) request(method string, params any) (Value, error) {
	session, err := m.ensureSession()
	if err != nil {
		return Null, err
	}
	body, status, err := m.post(method, params, session, true)
	if status == http.StatusNotFound {
		// The server forgot the session (a deploy): start a new one and ask again
		m.forget(session)
		if session, err = m.ensureSession(); err != nil {
			return Null, err
		}
		body, _, err = m.post(method, params, session, true)
	}
	if err != nil {
		return Null, err
	}
	if message := body.Get("error"); !message.IsNull() {
		text := message.Get("message").S()
		if data := message.Get("data"); data.IsString() {
			text = data.S()
		}
		return Null, Failf("%s", text)
	}
	return body.Get("result"), nil
}

func (m *MCP) ensureSession() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.session != "" {
		return m.session, nil
	}
	initialize := map[string]any{"protocolVersion": Protocol, "capabilities": map[string]any{},
		"clientInfo": map[string]any{"name": "dobase", "version": m.client.userAgent}}
	body, _, headers, err := m.send(map[string]any{"jsonrpc": "2.0", "id": m.nextID(), "method": "initialize", "params": initialize}, "", true)
	if err != nil {
		return "", err
	}
	if message := body.Get("error"); !message.IsNull() {
		return "", Failf("The server refused to start: %s", message.Get("message").S())
	}
	session := headers.Get("Mcp-Session-Id")
	if session == "" {
		return "", Failf("%s has no MCP server. Is it a Dobase server from before MCP?", m.client.Base())
	}
	if _, _, _, err := m.send(map[string]any{"jsonrpc": "2.0", "method": "notifications/initialized"}, session, true); err != nil {
		return "", err
	}
	m.session = session
	return session, nil
}

func (m *MCP) forget(session string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.session == session {
		m.session = ""
	}
}

// Close ends the session on the server.
func (m *MCP) Close() {
	m.mu.Lock()
	session := m.session
	m.session = ""
	m.mu.Unlock()
	if session == "" {
		return
	}
	target, _ := m.client.urlFor("/mcp")
	if request, err := m.client.newRequest(Delete, target, nil); err == nil {
		request.Header.Set("Mcp-Session-Id", session)
		request.Header.Set("MCP-Protocol-Version", Protocol)
		if response, err := m.client.do(request); err == nil {
			response.Body.Close()
		}
	}
}

func (m *MCP) nextID() int {
	m.id++
	return m.id
}

func (m *MCP) post(method string, params any, session string, retry bool) (Value, int, error) {
	m.mu.Lock()
	id := m.nextID()
	m.mu.Unlock()
	body, status, _, err := m.send(map[string]any{"jsonrpc": "2.0", "id": id, "method": method, "params": params}, session, retry)
	return body, status, err
}

// send posts one message; a refused token is refreshed once and the message sent again.
func (m *MCP) send(message map[string]any, session string, retry bool) (Value, int, http.Header, error) {
	data, err := json.Marshal(message)
	if err != nil {
		return Null, 0, nil, Failf("Can't send %v: %v", message, err)
	}
	target, err := m.client.urlFor("/mcp")
	if err != nil {
		return Null, 0, nil, err
	}
	request, err := m.client.newRequest(Post, target, bytes.NewReader(data))
	if err != nil {
		return Null, 0, nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	request.Header.Set("MCP-Protocol-Version", Protocol)
	if session != "" {
		request.Header.Set("Mcp-Session-Id", session)
	}
	response, err := m.client.do(request)
	if err != nil {
		return Null, 0, nil, err
	}
	defer response.Body.Close()
	status := response.StatusCode

	if status == http.StatusUnauthorized && retry {
		if _, err := m.client.refresh(request); err != nil {
			return Null, status, nil, err
		}
		return m.send(message, session, false)
	}
	switch {
	case status == http.StatusAccepted || status == http.StatusNoContent:
		return Null, status, response.Header, nil
	case status == http.StatusNotFound && session != "":
		return Null, status, response.Header, nil
	case status == http.StatusTooManyRequests:
		return Null, status, nil, &Error{Kind: Failed, Message: "Too many requests: try again in a minute (HTTP 429)", Status: status}
	}
	raw, err := io.ReadAll(response.Body)
	if err != nil {
		return Null, status, nil, Failf("Could not read the response: %v", err)
	}
	if status < 200 || status >= 300 {
		if body, err := Parse(raw); err == nil && !body.Get("error").Get("message").IsNull() {
			return body, status, response.Header, nil
		}
		return Null, status, nil, apiError(status, raw)
	}
	body, err := Parse(raw)
	if err != nil {
		return Null, status, nil, Failf("The server sent something other than JSON (HTTP %d).", status)
	}
	return body, status, response.Header, nil
}

// Listen subscribes the session to uris and calls changed with the uri of
// each change the server tells of, until the stream ends or ctx is done. A
// stream ends now and then by itself (the server's limit is half an hour):
// the caller listens again.
func (m *MCP) Listen(ctx context.Context, uris []string, opened func(), changed func(uri string)) error {
	return m.ListenAlive(ctx, uris, opened, changed, nil)
}

// ListenAlive is Listen that also calls alive for whatever the stream says,
// the server's pings included, so a caller can tell a quiet stream from a dead one.
func (m *MCP) ListenAlive(ctx context.Context, uris []string, opened func(), changed func(uri string), alive func()) error {
	session, err := m.ensureSession()
	if err != nil {
		return err
	}
	target, err := m.client.urlFor("/mcp")
	if err != nil {
		return err
	}
	request, err := m.client.newRequest(Get, target, nil)
	if err != nil {
		return err
	}
	request = request.WithContext(ctx)
	request.Header.Set("Accept", "text/event-stream")
	// Not compressed: Thruster holds a compressed stream back, headers and all, until enough of it has come
	request.Header.Set("Accept-Encoding", "identity")
	request.Header.Set("MCP-Protocol-Version", Protocol)
	request.Header.Set("Mcp-Session-Id", session)
	response, err := m.client.http.Do(request)
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return Failf("Could not reach %s: %v", m.client.Base(), err)
	}
	defer response.Body.Close()
	switch response.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		m.forget(session)
		return Failf("The server forgot the session (HTTP 404)")
	case http.StatusUnauthorized:
		if _, err := m.client.refresh(request); err != nil {
			return err
		}
		return Failf("The token was refreshed (HTTP 401)")
	default:
		raw, _ := io.ReadAll(response.Body)
		return apiError(response.StatusCode, raw)
	}

	// Subscribed once the stream is there, so nothing said in between is missed
	for _, uri := range uris {
		if _, err := m.request("resources/subscribe", map[string]any{"uri": uri}); err != nil {
			return err
		}
	}
	if opened != nil {
		opened()
	}

	lines := bufio.NewScanner(response.Body)
	lines.Buffer(make([]byte, 64*1024), 1024*1024)
	for lines.Scan() {
		line := lines.Text()
		if alive != nil {
			alive()
		}
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		message, err := Parse([]byte(strings.TrimSpace(strings.TrimPrefix(line, "data:"))))
		if err != nil || message.Get("method").S() != "notifications/resources/updated" {
			continue
		}
		changed(message.Get("params", "uri").S())
	}
	if ctx.Err() != nil {
		return nil
	}
	if err := lines.Err(); err != nil {
		return Failf("The stream broke off: %v", err)
	}
	return Failf("The stream ended")
}

// Ping keeps the session from running out while nothing else is asked.
func (m *MCP) Ping() error {
	_, err := m.request("ping", map[string]any{})
	return err
}
