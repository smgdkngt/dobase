package commands

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"syscall"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/events"
)

func eventStream() []*Definition {
	return []*Definition{
		New("events", "Print what happened in your tools since last time, a line of JSON per event (--follow keeps listening)", nil, []Flag{
			Switch("follow", "Keep listening, and print every event the moment it happens"),
			Each("tool", "TOOL", "Only this tool's events; repeat for several"),
			Each("kind", "KIND", "Only this kind: a family (mail, card, chat) or one (card.moved); repeat for several"),
			Switch("skip-own", "Leave out what was done with this access token"),
			F("since", "WHEN", "Start that long ago (30m, 2h, 3d) or at a time, not where this listener was"),
			F("name", "NAME", "This listener's name, under which it remembers where it was (default: default)"),
			Switch("verbose", "Say on stderr what the connection is doing"),
		}, runEvents),
	}
}

func runEvents(ctx *Ctx, args *Args) error {
	name := args.Value("name")
	if name == "" {
		name = "default"
	}
	if !events.ValidName(name) {
		return api.Usagef("A listener's name is letters, digits, dashes, dots and underscores, got %s.", Quoted(name))
	}
	since, err := sinceParam(args.Value("since"), time.Now())
	if err != nil {
		return err
	}
	server, err := ctx.API()
	if err != nil {
		return err
	}
	filter := events.Filter{Kinds: args.All("kind"), SkipOwn: args.On("skip-own")}
	for _, reference := range args.All("tool") {
		tool, err := ctx.Tool(reference, "")
		if err != nil {
			return err
		}
		filter.Tools = append(filter.Tools, tool.Get("id").S())
	}

	bookmark, err := events.OpenBookmark(name, ctx.Config.URL())
	if err != nil {
		return err
	}
	defer bookmark.Close()

	// Only events go to stdout: whoever reads it is woken by every line
	var log func(string, ...any)
	if args.On("verbose") {
		log = func(format string, args ...any) {
			fmt.Fprintf(ctx.Err, "%s %s\n", time.Now().Format("15:04:05"), Clean(fmt.Sprintf(format, args...)))
		}
	}
	listener := &events.Listener{Server: server, Filter: filter, Out: ctx.Out, Bookmark: bookmark, Since: since, Log: log,
		Poll: 5 * time.Minute, Retry: time.Second, RetryMax: 30 * time.Second}
	if !args.On("follow") {
		return listener.Once()
	}

	line := &events.Line{Server: ctx.Config.URL(), Token: ctx.Config.Token(), UserAgent: ctx.UserAgent, Quiet: 20 * time.Second, Log: log}
	listener.Line = line.Listen
	// Stopped from outside (Ctrl+C, a session that ends) is the way a listener ends
	stopped, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return listener.Follow(stopped)
}

var ago = regexp.MustCompile(`^(\d+)([smhd])$`)

// sinceParam turns "2h" (that long ago) or a date or time into the time the API takes.
func sinceParam(value string, now time.Time) (string, error) {
	if value == "" {
		return "", nil
	}
	if match := ago.FindStringSubmatch(value); match != nil {
		count, _ := strconv.ParseInt(match[1], 10, 64)
		unit := map[string]time.Duration{"s": time.Second, "m": time.Minute, "h": time.Hour, "d": 24 * time.Hour}[match[2]]
		return now.Add(-time.Duration(count) * unit).UTC().Format(time.RFC3339), nil
	}
	if moment, err := time.Parse(time.RFC3339, value); err == nil {
		return moment.UTC().Format(time.RFC3339), nil
	}
	if day, err := time.ParseInLocation("2006-01-02", value, now.Location()); err == nil {
		return day.UTC().Format(time.RFC3339), nil
	}
	return "", api.Usagef("--since takes how long ago (30m, 2h, 3d), a date (2026-10-09) or a time (2026-10-09T08:00:00Z), got %s.", Quoted(value))
}
