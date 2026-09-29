package cli

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

const calendarResponses = `{
	"/tools": [{"id": 22, "name": "Family", "type": "calendar"}, {"id": 19, "name": "Stuff", "type": "files"}],
	"/tools/22/calendar": {"calendars": [{"id": 3, "name": "Work"}, {"id": 4, "name": "Home"}]},
	"/tools/22/calendar/events/5": {"id": 5, "all_day": false, "recurring": false,
		"starts_at": "2026-10-01T09:00:00+02:00", "ends_at": "2026-10-01T09:45:00+02:00"},
	"/tools/22/calendar/events/6": {"id": 6, "all_day": true, "recurring": true,
		"starts_at": "2026-10-03T00:00:00+02:00", "ends_at": "2026-10-05T23:59:59+02:00"},
	"/tools/19/files/items/7": {"id": 7, "name": "../../etc/report.pdf", "file_size": 2048}
}`

func calendarCtx(sent *[]api.Value) (*command.Ctx, *bytes.Buffer) {
	var out bytes.Buffer
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(newFakeAPI(calendarResponses, sent))
	return ctx, &out
}

func TestEventTimesAreSentAsWallClockTimes(t *testing.T) {
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"--start", "2026-10-01 14:30"},
			`{"all_day":false,"end_time":"2026-10-01 15:30","start_time":"2026-10-01 14:30","summary":"Meet"}`},
		{[]string{"--start", "2026-10-01T9:05", "--duration", "1H30m"},
			`{"all_day":false,"end_time":"2026-10-01 10:35","start_time":"2026-10-01 09:05","summary":"Meet"}`},
		// The night the clocks go back in Europe still has three hours in three hours.
		{[]string{"--start", "2026-10-25 01:30", "--duration", "3h"},
			`{"all_day":false,"end_time":"2026-10-25 04:30","start_time":"2026-10-25 01:30","summary":"Meet"}`},
		{[]string{"--start", "2026-10-31 23:30", "--end", "2026-11-01 00:15"},
			`{"all_day":false,"end_time":"2026-11-01 00:15","start_time":"2026-10-31 23:30","summary":"Meet"}`},
		{[]string{"--start", "2026-10-01", "--all-day"},
			`{"all_day":true,"end_time":"2026-10-01 23:59:59","start_time":"2026-10-01 00:00","summary":"Meet"}`},
		{[]string{"--start", "2026-12-30", "--end", "2027-01-02", "--all-day", "--calendar", "home"},
			`{"all_day":true,"calendar_id":4,"end_time":"2027-01-02 23:59:59","start_time":"2026-12-30 00:00","summary":"Meet"}`},
	} {
		var sent []api.Value
		ctx, _ := calendarCtx(&sent)
		if err := invoke(ctx, "event create", append([]string{"22", "Meet"}, c.args...)...); err != nil {
			t.Errorf("%v: %v", c.args, err)
			continue
		}
		if got := sent[0].Get("calendars_event").JSON(); got != c.want {
			t.Errorf("%v: sent %s", c.args, got)
		}
	}
}

func TestEventUpdatesKeepWhatIsNotGiven(t *testing.T) {
	for _, c := range []struct {
		args []string
		want string
	}{
		// A new start keeps the length; a new end or duration keeps the start.
		{[]string{"22/5", "--start", "2026-10-02 11:00"}, `{"all_day":false,"end_time":"2026-10-02 11:45","start_time":"2026-10-02 11:00"}`},
		{[]string{"22/5", "--duration", "2h"}, `{"all_day":false,"end_time":"2026-10-01 11:00"}`},
		{[]string{"22/5", "--all-day"}, `{"all_day":true,"end_time":"2026-10-01 23:59:59","start_time":"2026-10-01 00:00"}`},
		// An all-day event stays all day when only dates are given, and keeps its days.
		{[]string{"22/6", "--start", "2026-10-10"}, `{"all_day":true,"end_time":"2026-10-12 23:59:59","start_time":"2026-10-10 00:00"}`},
		{[]string{"22/6", "--end", "2026-10-10"}, `{"all_day":true,"end_time":"2026-10-10 23:59:59"}`},
		{[]string{"22/6", "--start", "2026-10-10 10:00"}, `{"all_day":false,"end_time":"2026-10-10 11:00","start_time":"2026-10-10 10:00"}`},
		{[]string{"22/6", "--repeat-count", "4"}, `{"recurrence_count":4,"recurrence_end_type":"count"}`},
		{[]string{"22/5", "--repeat", "weekly", "--repeat-until", "2026-12-01"},
			`{"recurrence_end_type":"until","recurrence_frequency":"weekly","recurrence_until":"2026-12-01"}`},
		{[]string{"22/5", "--repeat", "daily"}, `{"recurrence_end_type":"never","recurrence_frequency":"daily"}`},
		{[]string{"22/6", "--repeat", "none"}, `{"recurrence_frequency":"none"}`},
	} {
		var sent []api.Value
		ctx, _ := calendarCtx(&sent)
		if err := invoke(ctx, "event update", c.args...); err != nil {
			t.Errorf("%v: %v", c.args, err)
			continue
		}
		if got := sent[0].Get("calendars_event").JSON(); got != c.want {
			t.Errorf("%v: sent %s", c.args, got)
		}
	}
}

func TestEventInputIsCheckedBeforeAnythingIsSent(t *testing.T) {
	for _, c := range []struct {
		args []string
		want string
	}{
		{[]string{"event create", "22", "Meet"}, "--start is required. See `dobase help event`."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01"}, `--start needs a time, like "2026-10-01 14:30", or add --all-day.`},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 24:00"}, `--start has an invalid time: "2026-10-01 24:00".`},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 12:5"}, `--start expects "YYYY-MM-DD HH:MM", got "2026-10-01 12:5".`},
		{[]string{"event create", "22", "Meet", "--start", "Friday 10:00"}, `--start expects "YYYY-MM-DD HH:MM", got "Friday 10:00".`},
		{[]string{"event create", "22", "Meet", "--start", "2026-02-30 10:00"}, `Expected a date like 2026-10-01, today or tomorrow; got "2026-02-30".`},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--end", "2026-10-01 09:00"}, "--end is before the start."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--end", "2026-10-01 11:00", "--duration", "1h"}, "Use --end or --duration, not both."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01", "--all-day", "--duration", "1h"}, "--duration doesn't work for all-day events. Use --end DATE."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-05", "--all-day", "--end", "2026-10-01"}, "--end is before the start."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--repeat", "hourly"}, "--repeat must be one of: daily, weekly, monthly, yearly, none"},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--repeat-count", "3"}, "--repeat-until and --repeat-count need --repeat."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--repeat", "none", "--repeat-count", "3"}, "--repeat none can't have --repeat-until or --repeat-count."},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--repeat", "daily", "--repeat-count", "0"}, `--repeat-count expects a positive number, got "0".`},
		{[]string{"event create", "22", "Meet", "--start", "2026-10-01 10:00", "--repeat", "daily", "--repeat-until", "2026-11-01", "--repeat-count", "2"}, "Use --repeat-until or --repeat-count, not both."},
		{[]string{"event update", "22/5", "--repeat-count", "3"}, "Event 22/5 doesn't repeat. Add --repeat FREQUENCY."},
		{[]string{"event update", "22/5"}, "Nothing to update. See `dobase help event`."},
		{[]string{"event list", "22", "--to", "2026-10-01", "--days", "3"}, "Use --to or --days, not both."},
		{[]string{"event list", "22", "--days", "-1"}, `--days expects a positive number, got "-1".`},
	} {
		var sent []api.Value
		ctx, _ := calendarCtx(&sent)
		err := invoke(ctx, c.args[0], c.args[1:]...)
		if api.KindOf(err) != api.Usage || err.Error() != c.want {
			t.Errorf("%v: got %v", c.args, err)
		}
		if len(sent) > 0 {
			t.Errorf("%v: sent %v", c.args, sent)
		}
	}
}

func TestDurationsAreHoursAndMinutes(t *testing.T) {
	for duration, end := range map[string]string{"30m": "10:30", "1h": "11:00", "1h30m": "11:30", " 2H ": "12:00", "1h0m": "11:00", "90m": "11:30"} {
		var sent []api.Value
		ctx, _ := calendarCtx(&sent)
		if err := invoke(ctx, "event create", "22", "Meet", "--start", "2026-10-01 10:00", "--duration", duration); err != nil {
			t.Errorf("%q: %v", duration, err)
		} else if got := sent[0].Get("calendars_event", "end_time").S(); got != "2026-10-01 "+end {
			t.Errorf("%q: ends %s", duration, got)
		}
	}
	for _, duration := range []string{"90", "0m", "h30m", "1h2h", "m", "-1h", "1.5h", ""} {
		var sent []api.Value
		ctx, _ := calendarCtx(&sent)
		err := invoke(ctx, "event create", "22", "Meet", "--start", "2026-10-01 10:00", "--duration", duration)
		if err == nil || !strings.HasPrefix(err.Error(), "--duration expects a length like 30m, 1h or 1h30m, got ") {
			t.Errorf("%q: got %v", duration, err)
		}
	}
}

func TestFileDownloadsKeepOnlyTheLastPartOfTheName(t *testing.T) {
	t.Chdir(t.TempDir())
	var sent []api.Value
	ctx, out := calendarCtx(&sent)

	if err := invoke(ctx, "file download", "19/7"); err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile("report.pdf"); err != nil || string(data) != "data from /tools/19/files/items/7/download" {
		t.Errorf("saved %q, %v", data, err)
	}
	if want := "Downloaded ../../etc/report.pdf (2.0 KB) to report.pdf.\n"; out.String() != want {
		t.Errorf("out %q", out.String())
	}

	err := invoke(ctx, "file download", "19/7")
	if err == nil || err.Error() != "report.pdf already exists. Use --force to overwrite it." {
		t.Errorf("got %v", err)
	}
	if err := invoke(ctx, "file download", "19/7", "--force"); err != nil {
		t.Error(err)
	}

	if err := os.Mkdir("saved", 0o755); err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if err := invoke(ctx, "file download", "19/7", "--output", "./saved"); err != nil || !strings.HasSuffix(out.String(), "to ./saved/report.pdf.\n") {
		t.Errorf("out %q, %v", out.String(), err)
	}
	if err := invoke(ctx, "file download", "19/7", "--output", "missing/x.pdf"); err == nil || err.Error() != "missing is not a directory." {
		t.Errorf("got %v", err)
	}
}
