package commands

import (
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

var frequencies = []string{"daily", "weekly", "monthly", "yearly"}

const syncTimeout = 60 * time.Second

func eventFlags(updating bool) []Flag {
	flags := []Flag{
		F("start", "TIME", "Start: \"YYYY-MM-DD HH:MM\" in your Dobase time zone (a date with --all-day)"),
	}
	if updating {
		flags = append(flags,
			F("end", "TIME", "New end, like --start (a new --start alone keeps the length)"),
			F("duration", "DURATION", "New length instead of --end: 30m, 1h, 1h30m"))
	} else {
		flags = append(flags,
			F("end", "TIME", "End, like --start (default: --duration after the start)"),
			F("duration", "DURATION", "Length instead of --end: 30m, 1h, 1h30m (default 1h)"))
	}
	flags = append(flags,
		Switch("all-day", "All-day event: --start and --end are dates (--end defaults to --start)"),
		F("location", "TEXT", "Location"),
		F("description", "TEXT", "Description (plain text)"))
	if updating {
		flags = append(flags, F("calendar", "CALENDAR", "Move to this calendar (id or name)"))
	} else {
		flags = append(flags, F("calendar", "CALENDAR", "Calendar id or name (default: the default calendar)"))
	}
	flags = append(flags,
		F("repeat", "FREQUENCY", fmt.Sprintf("Repeat %s, or none to stop repeating", strings.Join(frequencies, ", "))),
		F("repeat-until", "DATE", "Repeat until this date (YYYY-MM-DD)"),
		F("repeat-count", "N", "Repeat N times"))
	if updating {
		flags = append(flags, F("title", "TEXT", "New title"))
	}
	return flags
}

func calendar() []*Definition {
	return []*Definition{
		New("event list", "List events by day: today and the next 6 days, unless you pick the days", []string{"TOOL"},
			[]Flag{
				F("from", "DATE", "First day: YYYY-MM-DD, today or tomorrow (default: today)"),
				F("to", "DATE", "Last day, included"),
				F("days", "N", "Number of days, instead of --to"),
			}, listEvents),
		New("event show", "Show an event; a repeating event shows as its whole series", []string{"TOOL/EVENT"}, nil, showEvent),
		New("event create", "Add an event to a calendar tool", []string{"TOOL", "TITLE"}, eventFlags(false), createEvent),
		New("event update", "Change an event; for a repeating event this changes the whole series", []string{"TOOL/EVENT"},
			eventFlags(true), updateEvent),
		New("event delete", "Delete an event; for a repeating event, every occurrence", []string{"TOOL/EVENT"}, nil, deleteEvent),
		New("calendar list", "List the calendars of a calendar tool and its sync status", []string{"TOOL"}, nil, listCalendars),
		New("calendar sync", "Sync a calendar tool with its CalDAV server and wait up to a minute for it", []string{"TOOL"}, nil, syncCalendar),
	}
}

func listEvents(ctx *Ctx, args *Args) error {
	from, hasFrom := args.Flag("from")
	to, hasTo := args.Flag("to")
	days, hasDays := args.Flag("days")
	if hasTo && hasDays {
		return api.Usagef("Use --to or --days, not both.")
	}

	tool, err := ctx.Tool(args.At(0), "calendar")
	if err != nil {
		return err
	}
	firstDay, lastDay := "", ""
	var first time.Time
	if hasFrom {
		if first, err = eventDay(from); err != nil {
			return err
		}
		firstDay = first.Format(DateLayout)
	}
	if hasTo {
		last, err := eventDay(to)
		if err != nil {
			return err
		}
		lastDay = last.Format(DateLayout)
	}
	if hasDays {
		if !hasFrom {
			first = Today()
			firstDay = first.Format(DateLayout)
		}
		count, err := positiveNumber(days, "--days")
		if err != nil {
			return err
		}
		lastDay = addDays(first, count-1).Format(DateLayout)
	}

	agenda, err := ctx.Get(fmt.Sprintf("/tools/%s/calendar", tool.Get("id").S()), "start_date", firstDay, "end_date", lastDay)
	if err != nil {
		return err
	}

	return ctx.Output(agenda, func() error {
		firstDay := dateOf(agenda.Get("start_date"))
		ctx.Sayf("%s (calendar %s): %s to %s", tool.Get("name").S(), tool.Get("id").S(), fullDay(firstDay), fullDay(dateOf(agenda.Get("end_date"))))
		events := agenda.Get("events").Items()
		if len(events) == 0 {
			ctx.Say("  (no events)")
		}

		// Events that began before the first day are listed under it.
		type listing struct {
			day    time.Time
			events []api.Value
		}
		var listings []*listing
		for _, event := range events {
			listedOn := dateOf(event.Get("starts_at"))
			if listedOn.Before(firstDay) {
				listedOn = firstDay
			}
			index := slices.IndexFunc(listings, func(l *listing) bool { return l.day.Equal(listedOn) })
			if index < 0 {
				listings = append(listings, &listing{day: listedOn})
				index = len(listings) - 1
			}
			listings[index].events = append(listings[index].events, event)
		}

		for _, listed := range listings {
			ctx.Blank()
			ctx.Say(listed.day.Format("Monday 2 January 2006"))
			// All-day events first, otherwise in the server's order.
			sort.SliceStable(listed.events, func(i, j int) bool {
				return listed.events[i].Get("all_day").Truthy() && !listed.events[j].Get("all_day").Truthy()
			})
			var rows [][]string
			for _, event := range listed.events {
				rows = append(rows, []string{
					timeRange(event, listed.day),
					tool.Get("id").S() + "/" + event.Get("id").S(),
					event.Get("summary").S(),
					eventDetails(event),
				})
			}
			ctx.Table(rows, 2)
		}
		return nil
	})
}

func showEvent(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "calendar", "event")
	if err != nil {
		return err
	}
	event, err := ctx.Get(fmt.Sprintf("/tools/%s/calendar/events/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	return ctx.Output(event, func() error {
		ctx.Sayf("%s (event %s/%s)", event.Get("summary").S(), tool.Get("id").S(), event.Get("id").S())
		ctx.Field("When", eventSpan(event))
		ctx.Field("Repeats", event.Get("recurrence").S())
		ctx.Field("Calendar", event.Get("calendar", "name").S())
		ctx.Field("Location", event.Get("location").S())
		ctx.Field("Status", event.Get("status").S())
		ctx.Field("Organizer", organizer(event.Get("organizer")))
		ctx.Field("Created by", Person(event.Get("creator")))
		ctx.Field("URL", event.Get("url").S())

		if description := event.Get("description").S(); strings.TrimSpace(description) != "" {
			ctx.Blank()
			ctx.Say("Description:")
			ctx.Paragraph(description, 2)
		}

		attendees := event.Get("attendees").Items()
		if len(attendees) > 0 {
			ctx.Blank()
			ctx.Sayf("Attendees (%d):", len(attendees))
			var rows [][]string
			for _, attendee := range attendees {
				rows = append(rows, []string{organizer(attendee), attendee.Get("status").S()})
			}
			ctx.Table(rows, 2)
		}
		return nil
	})
}

func createEvent(ctx *Ctx, args *Args) error {
	if _, ok := args.Flag("start"); !ok {
		return api.Usagef("--start is required. See `dobase help event`.")
	}

	tool, err := ctx.Tool(args.At(0), "calendar")
	if err != nil {
		return err
	}
	attributes, err := eventAttributes(ctx, tool, args, nil, true)
	if err != nil {
		return err
	}
	attributes["summary"] = args.At(1)
	event, err := ctx.Post(fmt.Sprintf("/tools/%s/calendar/events", tool.Get("id").S()), map[string]any{"calendars_event": attributes})
	if err != nil {
		return err
	}

	return ctx.Output(event, func() error {
		ctx.Sayf("Created event %s/%s %s in %s: %s", tool.Get("id").S(), event.Get("id").S(), Quoted(event.Get("summary").S()),
			event.Get("calendar", "name").S(), eventSpan(event))
		ctx.Field("Repeats", event.Get("recurrence").S())
		return nil
	})
}

func updateEvent(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "calendar", "event")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/calendar/events/%d", tool.Get("id").S(), id)

	changesTiming := args.Any("start", "end", "duration", "all-day")
	_, repeats := args.Flag("repeat")
	changesRepeatEnd := args.Any("repeat-until", "repeat-count") && !repeats
	var current *api.Value
	if changesTiming || changesRepeatEnd {
		event, err := ctx.Get(path)
		if err != nil {
			return err
		}
		current = &event
	}
	if changesRepeatEnd && !(current != nil && current.Get("recurring").Truthy()) {
		return api.Usagef("Event %s/%d doesn't repeat. Add --repeat FREQUENCY.", tool.Get("id").S(), id)
	}

	attributes, err := eventAttributes(ctx, tool, args, current, false)
	if err != nil {
		return err
	}
	if title, ok := args.Flag("title"); ok {
		attributes["summary"] = title
	}
	if len(attributes) == 0 {
		return api.Usagef("Nothing to update. See `dobase help event`.")
	}

	event, err := ctx.Patch(path, map[string]any{"calendars_event": attributes})
	if err != nil {
		return err
	}
	return ctx.Output(event, func() error {
		ctx.Sayf("Updated event %s/%s %s in %s: %s", tool.Get("id").S(), event.Get("id").S(), Quoted(event.Get("summary").S()),
			event.Get("calendar", "name").S(), eventSpan(event))
		ctx.Field("Repeats", event.Get("recurrence").S())
		return nil
	})
}

func deleteEvent(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "calendar", "event")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/calendar/events/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted event %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func listCalendars(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "calendar")
	if err != nil {
		return err
	}
	overview, err := calendarOverview(ctx, tool)
	if err != nil {
		return err
	}

	return ctx.Output(overview, func() error {
		ctx.Sayf("%s (calendar %s)", tool.Get("name").S(), tool.Get("id").S())
		ctx.Field("Sync", syncSummary(overview))
		ctx.Blank()
		var rows [][]string
		for _, calendar := range overview.Get("calendars").Items() {
			rows = append(rows, []string{calendar.Get("id").S(), calendar.Get("name").S(), calendar.Get("color").S(), calendarFlags(calendar)})
		}
		ctx.Table(rows, 2)
		return nil
	})
}

func syncCalendar(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "calendar")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/calendar/sync", tool.Get("id").S())

	status, err := ctx.Post(path, map[string]any{})
	if err != nil {
		return err
	}
	deadline := time.Now().Add(syncTimeout)
	for status.Get("status").S() == "syncing" && time.Now().Before(deadline) {
		time.Sleep(time.Second)
		if status, err = ctx.Get(path); err != nil {
			return err
		}
	}

	name := fmt.Sprintf("%s (calendar %s)", tool.Get("name").S(), tool.Get("id").S())
	state := status.Get("status").S()
	err = ctx.Output(status, func() error {
		switch state {
		case "synced":
			ctx.Sayf("Synced %s at %s.", name, Moment(status.Get("last_synced_at")))
		case "syncing":
			ctx.Sayf("%s is still syncing. Check later with `dobase calendar list %s`.", name, tool.Get("id").S())
		}
		return nil
	})
	// A failed sync fails the command, with --json too.
	if err == nil && state != "synced" && state != "syncing" {
		return api.Failf("Syncing %s failed. Check its calendar account in the browser.", name)
	}
	return err
}

// calendarOverview is the calendar for a single day: enough for its calendars and sync status.
func calendarOverview(ctx *Ctx, tool api.Value) (api.Value, error) {
	today := Today().Format(DateLayout)
	return ctx.Get(fmt.Sprintf("/tools/%s/calendar", tool.Get("id").S()), "start_date", today, "end_date", today)
}

// -- Input -------------------------------------------------------------------

func eventAttributes(ctx *Ctx, tool api.Value, args *Args, current *api.Value, creating bool) (map[string]any, error) {
	attributes, err := timingAttributes(args, current)
	if err != nil {
		return nil, err
	}
	if location, ok := args.Flag("location"); ok {
		if attributes["location"], err = ctx.Text(location); err != nil {
			return nil, err
		}
	}
	if description, ok := args.Flag("description"); ok {
		text, err := ctx.Text(description)
		if err != nil {
			return nil, err
		}
		attributes["description"] = strings.TrimRightFunc(text, unicode.IsSpace)
	}
	if calendar, ok := args.Flag("calendar"); ok {
		calendars, err := calendarOverview(ctx, tool)
		if err != nil {
			return nil, err
		}
		found, err := findNamed(calendars.Get("calendars").Items(), calendar, "name", "calendar", "Calendars", tool.Get("name").S())
		if err != nil {
			return nil, err
		}
		attributes["calendar_id"] = found.Get("id")
	}
	recurrence, err := recurrenceAttributes(args, creating)
	if err != nil {
		return nil, err
	}
	for key, value := range recurrence {
		attributes[key] = value
	}
	return attributes, nil
}

// when is a --start or --end value: its date, and its time unless it was a date alone.
type when struct {
	flag           string
	date           time.Time
	hasTime        bool
	hours, minutes int
}

// timingAttributes are start_time, end_time and all_day from --start, --end,
// --duration and --all-day. When updating, current is the event: what isn't
// given stays as it is, and a new start keeps the event's length.
func timingAttributes(args *Args, current *api.Value) (map[string]any, error) {
	if !args.Any("start", "end", "duration", "all-day") {
		return map[string]any{}, nil
	}
	if args.On("end") && args.On("duration") {
		return nil, api.Usagef("Use --end or --duration, not both.")
	}

	var start, finish *when
	var err error
	if value, ok := args.Flag("start"); ok {
		if start, err = timeParam(value, "--start"); err != nil {
			return nil, err
		}
	}
	if value, ok := args.Flag("end"); ok {
		if finish, err = timeParam(value, "--end"); err != nil {
			return nil, err
		}
	}
	staysAllDay := current != nil && current.Get("all_day").Truthy() &&
		(start == nil || !start.hasTime) && (finish == nil || !finish.hasTime)

	if args.On("all-day") || staysAllDay {
		return allDayTiming(start, finish, args, current)
	}
	return timedTiming(start, finish, args, current)
}

// allDayTiming: all-day events run from the start of the first day to the end of the last.
func allDayTiming(start, finish *when, args *Args, current *api.Value) (map[string]any, error) {
	if args.On("duration") {
		return nil, api.Usagef("--duration doesn't work for all-day events. Use --end DATE.")
	}
	currentAllDay := current != nil && current.Get("all_day").Truthy()

	var first time.Time
	switch {
	case start != nil:
		first = start.date
	case current != nil:
		first = dateOf(current.Get("starts_at"))
	default:
		return nil, api.Usagef("--start is required. See `dobase help event`.")
	}
	var last time.Time
	switch {
	case finish != nil:
		last = finish.date
	case start != nil && currentAllDay:
		last = addDays(first, daysBetween(dateOf(current.Get("starts_at")), dateOf(current.Get("ends_at"))))
	case start != nil:
		last = first
	case current != nil:
		last = dateOf(current.Get("ends_at"))
		if last.Before(first) {
			last = first
		}
	default:
		last = first
	}
	if last.Before(first) {
		return nil, api.Usagef("--end is before the start.")
	}

	attributes := map[string]any{"all_day": true, "end_time": last.Format(DateLayout) + " 23:59:59"}
	if start != nil || !currentAllDay {
		attributes["start_time"] = first.Format(DateLayout) + " 00:00"
	}
	return attributes, nil
}

func timedTiming(start, finish *when, args *Args, current *api.Value) (map[string]any, error) {
	for _, given := range []*when{start, finish} {
		if given != nil && !given.hasTime {
			return nil, api.Usagef("%s needs a time, like \"2026-10-01 14:30\", or add --all-day.", given.flag)
		}
	}
	currentTimed := current != nil && !current.Get("all_day").Truthy()

	var starts time.Time
	var err error
	switch {
	case start != nil:
		starts = wallClock(start)
	case current != nil:
		if starts, err = wallClockOf(current.Get("starts_at")); err != nil {
			return nil, err
		}
	default:
		return nil, api.Usagef("--start is required. See `dobase help event`.")
	}

	var ends time.Time
	duration, hasDuration := args.Flag("duration")
	switch {
	case finish != nil:
		ends = wallClock(finish)
	case hasDuration:
		length, err := durationParam(duration)
		if err != nil {
			return nil, err
		}
		ends = starts.Add(length)
	case currentTimed:
		currentEnds, err := wallClockOf(current.Get("ends_at"))
		if err != nil {
			return nil, err
		}
		currentStarts, err := wallClockOf(current.Get("starts_at"))
		if err != nil {
			return nil, err
		}
		ends = starts.Add(currentEnds.Sub(currentStarts))
	default:
		ends = starts.Add(time.Hour)
	}
	if ends.Before(starts) {
		return nil, api.Usagef("--end is before the start.")
	}

	attributes := map[string]any{"all_day": false, "end_time": clockParam(ends)}
	if start != nil || current == nil || current.Get("all_day").Truthy() {
		attributes["start_time"] = clockParam(starts)
	}
	return attributes, nil
}

func recurrenceAttributes(args *Args, creating bool) (map[string]any, error) {
	repeat, repeats := args.Flag("repeat")
	until, hasUntil := args.Flag("repeat-until")
	count, hasCount := args.Flag("repeat-count")
	attributes := map[string]any{}
	if !repeats && !hasUntil && !hasCount {
		return attributes, nil
	}

	if hasUntil && hasCount {
		return nil, api.Usagef("Use --repeat-until or --repeat-count, not both.")
	}
	if repeats && !slices.Contains(frequencies, repeat) && repeat != "none" {
		return nil, api.Usagef("--repeat must be one of: %s, none", strings.Join(frequencies, ", "))
	}
	if repeats && repeat == "none" && (hasUntil || hasCount) {
		return nil, api.Usagef("--repeat none can't have --repeat-until or --repeat-count.")
	}
	if creating && !repeats {
		return nil, api.Usagef("--repeat-until and --repeat-count need --repeat.")
	}

	if repeats {
		attributes["recurrence_frequency"] = repeat
	}
	switch {
	case hasUntil:
		day, err := eventDay(until)
		if err != nil {
			return nil, err
		}
		attributes["recurrence_end_type"] = "until"
		attributes["recurrence_until"] = day.Format(DateLayout)
	case hasCount:
		number, err := positiveNumber(count, "--repeat-count")
		if err != nil {
			return nil, err
		}
		attributes["recurrence_end_type"] = "count"
		attributes["recurrence_count"] = number
	case !repeats || repeat != "none":
		attributes["recurrence_end_type"] = "never"
	}
	return attributes, nil
}

// timeParam reads "YYYY-MM-DD HH:MM" or a date alone; today and tomorrow work too.
func timeParam(value, flag string) (*when, error) {
	invalid := api.Usagef("%s expects \"YYYY-MM-DD HH:MM\", got %s.", flag, Quoted(value))
	trimmed := strings.TrimSpace(value)
	day, clockText, hasTime := trimmed, "", false
	if index := strings.IndexAny(trimmed, " T"); index >= 0 {
		day, clockText, hasTime = trimmed[:index], trimmed[index+1:], true
	}
	dayOK := day == "today" || day == "tomorrow" ||
		(len(day) == 10 && strings.Trim(day, "0123456789-") == "")
	if !dayOK {
		return nil, invalid
	}

	given := &when{flag: flag, hasTime: hasTime}
	if hasTime {
		hours, minutes, ok := strings.Cut(clockText, ":")
		if !ok || !(IsDigits(hours) && len(hours) <= 2 && IsDigits(minutes) && len(minutes) == 2) {
			return nil, invalid
		}
		given.hours, _ = strconv.Atoi(hours)
		given.minutes, _ = strconv.Atoi(minutes)
		if given.hours > 23 || given.minutes > 59 {
			return nil, api.Usagef("%s has an invalid time: %s.", flag, Quoted(value))
		}
	}
	date, err := eventDay(day)
	if err != nil {
		return nil, err
	}
	given.date = date
	return given, nil
}

// eventDay reads YYYY-MM-DD, today or tomorrow.
func eventDay(value string) (time.Time, error) {
	date, err := DateParam(value)
	if err != nil || date == "" {
		return time.Time{}, api.Usagef("Expected a date like 2026-10-01, today or tomorrow; got %s.", Quoted(value))
	}
	parsed, _ := ParseDate(date)
	return parsed, nil
}

// durationParam reads "30m", "1h" or "1h30m".
func durationParam(value string) (time.Duration, error) {
	text := strings.ToLower(strings.TrimSpace(value))
	hours, rest, hasHours := strings.Cut(text, "h")
	if !hasHours {
		hours, rest = "", text
	}
	minutes := strings.TrimSuffix(rest, "m")
	valid := (hours == "" || IsDigits(hours)) &&
		(minutes == "" || (strings.HasSuffix(rest, "m") && IsDigits(minutes))) &&
		!(strings.Contains(text, "h") && hours == "")
	var seconds int64
	if valid {
		h, _ := strconv.ParseInt(hours, 10, 64)
		m, _ := strconv.ParseInt(minutes, 10, 64)
		seconds = h*3600 + m*60
	}
	if seconds <= 0 {
		return 0, api.Usagef("--duration expects a length like 30m, 1h or 1h30m, got %s.", Quoted(value))
	}
	return time.Duration(seconds) * time.Second, nil
}

func positiveNumber(value, flag string) (int64, error) {
	number, err := strconv.ParseInt(value, 10, 64)
	if err != nil || number <= 0 {
		return 0, api.Usagef("%s expects a positive number, got %s.", flag, Quoted(value))
	}
	return number, nil
}

// Times are wall-clock times in the user's Dobase time zone, so they have no
// zone here: they're kept as UTC, where adding never meets a DST change.

func wallClock(given *when) time.Time {
	return given.date.Add(time.Duration(given.hours)*time.Hour + time.Duration(given.minutes)*time.Minute)
}

// wallClockOf reads the date and time of a timestamp from the server, ignoring its offset.
func wallClockOf(timestamp api.Value) (time.Time, error) {
	text := firstRunes(timestamp.S(), 16)
	if date, ok := ParseDate(text); ok {
		return date, nil
	}
	if len(text) > 11 && strings.ContainsRune(" Tt", rune(text[10])) {
		layout := "2006-01-02T15:04"
		if len(text) == 13 {
			layout = "2006-01-02T15"
		}
		if parsed, err := time.Parse(layout, text[:10]+"T"+text[11:]); err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, api.Failf("The server sent an odd time: %s", text)
}

func clockParam(moment time.Time) string {
	return moment.Format("2006-01-02 15:04")
}

// addDays leaves the date as it is when the result would be out of range.
func addDays(date time.Time, days int64) time.Time {
	if days > 7_300_000 || days < -7_300_000 {
		return date
	}
	moved := date.AddDate(0, 0, int(days))
	if moved.Year() < -9999 || moved.Year() > 9999 {
		return date
	}
	return moved
}

func daysBetween(from, to time.Time) int64 {
	return (to.Unix() - from.Unix()) / 86400
}

// -- Output ------------------------------------------------------------------

func firstRunes(text string, n int) string {
	runes := []rune(text)
	if len(runes) > n {
		runes = runes[:n]
	}
	return string(runes)
}

// dateOf is the date of a timestamp, or today if it has none.
func dateOf(timestamp api.Value) time.Time {
	if date, ok := ParseDate(firstRunes(timestamp.S(), 10)); ok {
		return date
	}
	return Today()
}

func clock(timestamp api.Value) string {
	runes := []rune(timestamp.S())
	if len(runes) <= 11 {
		return ""
	}
	return firstRunes(string(runes[11:]), 5)
}

func shortDay(date time.Time) string { return date.Format("Mon 2 Jan") }

func fullDay(date time.Time) string { return date.Format("Mon 2 Jan 2006") }

func eventSpan(event api.Value) string {
	startsOn, endsOn := dateOf(event.Get("starts_at")), dateOf(event.Get("ends_at"))
	starts, ends := clock(event.Get("starts_at")), clock(event.Get("ends_at"))

	switch {
	case event.Get("all_day").Truthy() && endsOn.After(startsOn):
		return fmt.Sprintf("%s to %s, all day", fullDay(startsOn), fullDay(endsOn))
	case event.Get("all_day").Truthy():
		return fullDay(startsOn) + ", all day"
	case endsOn.Equal(startsOn):
		return fmt.Sprintf("%s %s–%s", fullDay(startsOn), starts, ends)
	default:
		return fmt.Sprintf("%s %s to %s %s", fullDay(startsOn), starts, fullDay(endsOn), ends)
	}
}

// timeRange is the time of an event listed under listedOn.
func timeRange(event api.Value, listedOn time.Time) string {
	startsOn, endsOn := dateOf(event.Get("starts_at")), dateOf(event.Get("ends_at"))

	if event.Get("all_day").Truthy() {
		if endsOn.After(listedOn) {
			return "all day until " + shortDay(endsOn)
		}
		return "all day"
	}
	from := clock(event.Get("starts_at"))
	if !startsOn.Equal(listedOn) {
		from = shortDay(startsOn) + " " + from
	}
	till := clock(event.Get("ends_at"))
	if !endsOn.Equal(startsOn) {
		till = shortDay(endsOn) + " " + till
	}
	return from + "–" + till
}

func eventDetails(event api.Value) string {
	status := event.Get("status").S()
	return Join(" · ",
		event.Get("calendar", "name").S(),
		event.Get("location").S(),
		If(event.Get("recurring").Truthy(), "repeats"),
		If(status == "tentative" || status == "cancelled", status),
	)
}

// organizer is "Name <email>" of a contact, or "" for none.
func organizer(contact api.Value) string {
	if contact.IsNull() {
		return ""
	}
	email := contact.Get("email")
	return Join(" ", contact.Get("name").S(), If(!email.IsNull(), "<"+email.S()+">"))
}

func syncSummary(overview api.Value) string {
	if overview.Get("local").Truthy() {
		return "none, events are kept in Dobase"
	}
	lastSynced := "never"
	if at := overview.Get("sync", "last_synced_at"); !at.IsNull() {
		lastSynced = Moment(at)
	}
	return fmt.Sprintf("%s, last synced %s", overview.Get("sync", "status").S(), lastSynced)
}

func calendarFlags(calendar api.Value) string {
	return Join(", ",
		If(calendar.Get("is_default").Truthy(), "default"),
		If(calendar.Get("read_only").Truthy(), "read-only"),
		If(!calendar.Get("enabled").Truthy(), "disabled"),
	)
}
