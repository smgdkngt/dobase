// Package events is `dobase events`: what happens in someone's tools, printed
// one line of JSON per event.
//
// The server numbers its events and hands out "everything after N" (GET
// /events). A listener remembers the number of the last line it printed
// (Bookmark), so whatever happens to it in between, a restart, a network that
// went away, a server that was deployed, it goes on where it was: nothing is
// missed and nothing printed twice.
//
// To hear of an event when it happens, the listener keeps a WebSocket open
// (Line) over which the server only says "there is something", and then asks.
// A signal that got lost costs time, never an event: it also asks after every
// reconnect and every few minutes.
package events

import (
	"context"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Filter is which events a listener wants.
type Filter struct {
	// Tools are tool ids; none is every tool.
	Tools []string
	// Kinds are kinds ("card.moved") or families of them ("mail"); none is every kind.
	Kinds []string
	// SkipOwn leaves out what was done with the token that listens.
	SkipOwn bool
}

// Listener prints events and keeps its place.
type Listener struct {
	// Server answers GET /events.
	Server api.API
	Filter Filter
	// Out gets a line per event, and nothing else: each line wakes whoever reads it.
	Out io.Writer
	// Bookmark is where the listener was, and is kept as it goes.
	Bookmark *Bookmark
	// Since starts at a time (RFC 3339) instead of where the bookmark is.
	Since string
	// Log is told what the listener is doing, when someone wants to know.
	Log func(format string, args ...any)

	// Line says when there is something new, until it breaks. Follow only.
	Line func(ctx context.Context, heard func()) error
	// Poll is how often to ask without having heard anything.
	Poll time.Duration
	// Retry is how long to wait before asking or connecting again after a failure, at first and at most.
	Retry, RetryMax time.Duration
}

// Gone is a listener that can't go on: its token was revoked, or the server has no events.
type Gone struct{ Reason string }

func (g *Gone) Error() string { return g.Reason }

// Once prints what there is since the last time, and stops.
func (l *Listener) Once() error {
	return l.catchUp()
}

// Follow prints what there is, and then every event as it happens, until ctx is done.
func (l *Listener) Follow(ctx context.Context) error {
	// The first question is asked before anything else, so a wrong token or a
	// wrong filter is said at once and not after a connection was made
	if err := l.catchUp(); err != nil && permanent(err) {
		return err
	}

	heard := make(chan struct{}, 1)
	wake := func() {
		select {
		case heard <- struct{}{}:
		default:
		}
	}
	go l.keepLine(ctx, wake)

	poll := time.NewTicker(l.Poll)
	defer poll.Stop()
	wait := l.Retry
	// One wait at a time: asking again is never planned twice over
	var again <-chan time.Time
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-heard:
		case <-poll.C:
		case <-again:
		}

		again = nil
		err := l.catchUp()
		switch {
		case err == nil:
			wait = l.Retry
		case permanent(err):
			return err
		default:
			// The server is away for a moment (a deploy, a network that dropped): ask again soon
			l.log("Couldn't ask for events (%v); again in %s", err, wait)
			again = time.After(wait)
			wait = min(wait*2, l.RetryMax)
		}
	}
}

// keepLine holds the line open, and makes it again whenever it breaks.
func (l *Listener) keepLine(ctx context.Context, wake func()) {
	wait := l.Retry
	for ctx.Err() == nil {
		started := time.Now()
		err := l.Line(ctx, wake)
		if ctx.Err() != nil {
			return
		}
		// Whatever broke the line, ask: a revoked token is found out by the answer
		wake()
		if time.Since(started) > l.RetryMax {
			wait = l.Retry
		}
		// Not all at the same moment, when a server comes back to many listeners
		pause := wait + time.Duration(rand.Int64N(int64(wait)/2+1))
		l.log("The line broke (%v); connecting again in %s", err, pause.Round(time.Millisecond))
		select {
		case <-ctx.Done():
			return
		case <-time.After(pause):
		}
		wait = min(wait*2, l.RetryMax)
	}
}

// catchUp prints every event after the bookmark, a page at a time.
func (l *Listener) catchUp() error {
	for {
		page, err := l.ask()
		if err != nil {
			return err
		}
		if page.Get("gap").Truthy() {
			// Events after the bookmark are gone (kept for a week), or the number is
			// not this server's: said as a line of its own, so the reader looks for itself
			if err := l.print(api.Object("kind", "stream.gap", "at", time.Now().UTC().Format(time.RFC3339),
				"after", l.Bookmark.Cursor, "data", api.Object("reason", "Events after this number are no longer kept. Look at your tools for what you missed."))); err != nil {
				return err
			}
		}
		for _, event := range page.Get("events").Items() {
			if err := l.print(event); err != nil {
				return err
			}
			// Kept after each line: stopped halfway through a page, the rest comes next time
			if err := l.Bookmark.Move(event.Get("id").Int()); err != nil {
				return err
			}
		}
		// The server's number goes on past what wasn't for this listener
		if err := l.Bookmark.Move(page.Get("cursor").Int()); err != nil {
			return err
		}
		l.Since = ""
		if !page.Get("more").Truthy() {
			return nil
		}
	}
}

func (l *Listener) ask() (api.Value, error) {
	var params []api.Param
	switch {
	case l.Since != "":
		params = append(params, api.Param{Name: "since", Value: l.Since})
	case l.Bookmark.Known:
		params = append(params, api.Param{Name: "after", Value: strconv.FormatInt(l.Bookmark.Cursor, 10)})
	}
	for _, tool := range l.Filter.Tools {
		params = append(params, api.Param{Name: "tool[]", Value: tool})
	}
	for _, kind := range l.Filter.Kinds {
		params = append(params, api.Param{Name: "kind[]", Value: kind})
	}
	if l.Filter.SkipOwn {
		params = append(params, api.Param{Name: "skip_own", Value: "1"})
	}

	page, err := l.Server.Request(api.Get, "/events", params, nil)
	switch api.StatusOf(err) {
	case http.StatusUnauthorized:
		return api.Null, &Gone{"The access token was revoked or is not valid. Run `dobase login` for a new one."}
	case http.StatusNotFound:
		return api.Null, &Gone{"This server has no events yet: it is older than this dobase."}
	}
	// A proxy's own page while the server is away, say: not to be taken for "nothing new"
	if err == nil && (page.Get("cursor").IsNull() || !page.Get("events").IsArray()) {
		err = api.Failf("The server sent something that is no list of events.")
	}
	return page, err
}

// print writes one event as one line. A line is all of it or none of it, and
// what other people wrote can't break out of it: JSON has no raw newlines.
func (l *Listener) print(event api.Value) error {
	if _, err := fmt.Fprintln(l.Out, plain(event.JSON())); err != nil {
		return &Gone{fmt.Sprintf("Nobody reads the events any more: %v", err)}
	}
	return nil
}

// plain writes the characters that do something to a terminal, or turn the
// direction of writing around, the way JSON spells them out. The server takes
// them out of what it sends; a line is safe to show whatever server sent it.
// Outside a string JSON has none of these, so the line stays the same JSON.
func plain(line string) string {
	var out strings.Builder
	for _, char := range line {
		hidden := (char >= 0x7f && char <= 0x9f) || char == 0x061c || char == 0x200e || char == 0x200f ||
			(char >= 0x202a && char <= 0x202e) || (char >= 0x2066 && char <= 0x2069) || char == 0xfeff
		if hidden {
			fmt.Fprintf(&out, `\u%04x`, char)
		} else {
			out.WriteRune(char)
		}
	}
	return out.String()
}

func (l *Listener) log(format string, args ...any) {
	if l.Log != nil {
		l.Log(format, args...)
	}
}

// permanent says whether asking again can't help: the listener is gone, or the
// server refused the question itself (a filter it doesn't know).
func permanent(err error) bool {
	if _, gone := err.(*Gone); gone {
		return true
	}
	status := api.StatusOf(err)
	return status >= 400 && status < 500 && status != http.StatusRequestTimeout && status != http.StatusTooManyRequests
}
