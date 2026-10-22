package events

import (
	"context"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Resource is what a listener subscribes to on the server's MCP stream: that
// there is a new event for this person (Mcp::Live on the server).
const Resource = "dobase://events"

// Line is the server's MCP stream, over which it says that there is a new
// event. Nothing that is in a tool comes over it, only "there is something";
// the listener then asks for the events with a call of its own.
type Line struct {
	Server *api.MCP
	// Quiet is how long the stream may say nothing before it counts as dead.
	// The server pings every thirty seconds.
	Quiet time.Duration
	Log   func(format string, args ...any)
}

// Listen opens the stream, subscribes and calls heard for every signal,
// until the stream breaks or ctx is done. It always ends with why.
func (l *Line) Listen(ctx context.Context, heard func()) error {
	listening, cancel := context.WithCancel(ctx)
	defer cancel()

	// A stream that goes quiet (a laptop that slept, a connection that died on
	// the way) is ended here: the server's pings stop coming
	alive := make(chan struct{}, 1)
	go func() {
		timer := time.NewTimer(l.Quiet)
		defer timer.Stop()
		for {
			select {
			case <-listening.Done():
				return
			case <-alive:
				timer.Reset(l.Quiet)
			case <-timer.C:
				l.log("The stream said nothing for %s", l.Quiet)
				cancel()
				return
			}
		}
	}()
	beat := func() {
		select {
		case alive <- struct{}{}:
		default:
		}
	}

	err := l.Server.ListenAlive(listening, []string{Resource}, func() {
		l.log("Listening for events")
		beat()
	}, func(string) {
		beat()
		heard()
	}, beat)
	if ctx.Err() != nil {
		return nil
	}
	if listening.Err() != nil {
		return api.Failf("the stream went quiet")
	}
	return err
}

func (l *Line) log(format string, args ...any) {
	if l.Log != nil {
		l.Log(format, args...)
	}
}
