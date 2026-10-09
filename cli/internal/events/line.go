package events

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/websocket"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// The one channel a token's connection may open (EventsChannel on the server).
const subscription = `{"channel":"EventsChannel"}`

// Line is the WebSocket over which the server says that there is a new event:
// its Action Cable, where the app's own pages hear what changes. Nothing that
// is in a tool comes over it, only "there is something"; the listener then
// asks for the events with a request of its own.
type Line struct {
	// Server is the server's address, as in the config.
	Server string
	Token  string
	// UserAgent names this program to the server.
	UserAgent string
	// Quiet is how long the line may say nothing before it counts as dead.
	// The server says "ping" every three seconds.
	Quiet time.Duration
	Log   func(format string, args ...any)
}

// Listen connects, subscribes and calls heard for every signal, until the
// line breaks or ctx is done. It always ends with why.
func (l *Line) Listen(ctx context.Context, heard func()) error {
	config, err := l.config()
	if err != nil {
		return err
	}
	dialing, cancel := context.WithTimeout(ctx, l.Quiet)
	ws, err := config.DialContext(dialing)
	cancel()
	if err != nil {
		return fmt.Errorf("couldn't connect: %w", reason(err))
	}
	defer ws.Close()
	// What the server says here is a few words; nothing long is ever expected
	ws.MaxPayloadBytes = 64 << 10

	// A read that waits is only ended by closing the line
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			ws.Close()
		case <-done:
		}
	}()

	subscribed := false
	asked := time.Time{}
	for {
		ws.SetReadDeadline(time.Now().Add(l.Quiet))
		var text string
		if err := websocket.Message.Receive(ws, &text); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return fmt.Errorf("the line went quiet: %w", err)
		}
		message, err := api.Parse([]byte(text))
		if err != nil {
			continue
		}

		switch message.Get("type").S() {
		case "welcome":
			ws.SetWriteDeadline(time.Now().Add(l.Quiet))
			if err := websocket.Message.Send(ws, api.Object("command", "subscribe", "identifier", subscription).JSON()); err != nil {
				return fmt.Errorf("couldn't subscribe: %w", err)
			}
			asked = time.Now()
		case "confirm_subscription":
			subscribed = true
			l.log("Listening to %s", l.Server)
			// What happened while the line was being made was signalled to nobody
			heard()
		case "reject_subscription":
			return fmt.Errorf("the server doesn't let this token listen")
		case "disconnect":
			return fmt.Errorf("the server closed the line (%s)", message.Get("reason").Or("no reason given"))
		case "ping":
			// A server that never answers the subscription (one from before events) keeps pinging
			if !subscribed && !asked.IsZero() && time.Since(asked) > l.Quiet {
				return fmt.Errorf("the server didn't answer the subscription")
			}
		default:
			if message.Has("message") && message.Get("identifier").S() == subscription {
				heard()
			}
		}
	}
}

// config is the address of the server's cable and what to say when connecting.
// The token goes in a header, to the configured server only: a WebSocket
// handshake follows no redirects.
func (l *Line) config() (*websocket.Config, error) {
	server, err := url.Parse(strings.TrimRight(l.Server, "/"))
	if err != nil || server.Host == "" {
		return nil, api.Failf("%s is not a URL.", l.Server)
	}
	cable := *server
	switch server.Scheme {
	case "https":
		cable.Scheme = "wss"
	case "http":
		cable.Scheme = "ws"
	default:
		return nil, api.Failf("%s is not a URL.", l.Server)
	}
	cable.Path = strings.TrimRight(server.Path, "/") + "/cable"

	// Action Cable only takes a connection whose Origin is the server's own address
	config, err := websocket.NewConfig(cable.String(), server.Scheme+"://"+server.Host)
	if err != nil {
		return nil, api.Failf("%s is not a URL.", l.Server)
	}
	config.Header = http.Header{}
	config.Header.Set("Authorization", "Bearer "+l.Token)
	config.Header.Set("User-Agent", l.UserAgent)
	return config, nil
}

func (l *Line) log(format string, args ...any) {
	if l.Log != nil {
		l.Log(format, args...)
	}
}

// reason is why dialing failed, without the config the library wraps around it
// (which holds the token's header).
func reason(err error) error {
	if dial, ok := err.(*websocket.DialError); ok {
		return dial.Err
	}
	return err
}
