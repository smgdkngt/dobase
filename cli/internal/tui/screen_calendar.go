package tui

// A calendar as an agenda: two weeks of events, day by day.

import (
	"slices"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var calendarHints = []hint{{"↑↓", "scroll"}, {"h l", "week"}, {"t", "today"}, {"o", "browser"}, {"esc", "home"}}

var calendarHelp = []hint{
	{"↑ ↓ / j k", "Scroll"},
	{"h l / ← →", "A week earlier or later"},
	{"t", "Back to today"},
	{"o", "Open the calendar in your browser"},
	{"r", "Reload"},
	{"esc", "Back home"},
}

const calendarDays = 14

type Calendar struct {
	notLive
	tool     api.Value
	start    time.Time
	events   []api.Value
	local    bool
	selected int
}

// agendaRow is a day header (no event) or an event on that day.
type agendaRow struct {
	day   time.Time
	event *api.Value
}

func loadCalendar(app *App, tool api.Value) (*Calendar, error) {
	return loadCalendarFrom(app, tool, command.Today())
}

func loadCalendarFrom(app *App, tool api.Value, start time.Time) (*Calendar, error) {
	end := start.AddDate(0, 0, calendarDays-1)
	agenda, err := app.get(toolPath(tool)+"/calendar",
		api.Param{Name: "start_date", Value: start.Format(command.DateLayout)},
		api.Param{Name: "end_date", Value: end.Format(command.DateLayout)})
	if err != nil {
		return nil, err
	}
	return &Calendar{tool: tool, start: start, events: slices.Clone(agenda.Get("events").Items()), local: agenda.Get("local").Truthy()}, nil
}

func (s *Calendar) Tool() (api.Value, bool) { return s.tool, true }
func (s *Calendar) Hints() []hint           { return calendarHints }
func (s *Calendar) Help() []hint            { return calendarHelp }
func (s *Calendar) Refresh() Job            { return shiftCalendar(s.tool, s.start, 0) }

func (s *Calendar) Key(key Key, view *View, fx *Fx) bool {
	switch {
	case key.Is('h') || key.Code == KeyLeft:
		fx.job("Going back a week", shiftCalendar(s.tool, s.start, -7))
	case key.Is('l') || key.Code == KeyRight:
		fx.job("Going ahead a week", shiftCalendar(s.tool, s.start, 7))
	case key.Is('t'):
		fx.job("Back to today", shiftCalendar(s.tool, command.Today(), 0))
	default:
		return moveSelection(&s.selected, len(s.rows()), key)
	}
	return true
}

// rows are day headers and events, in order.
func (s *Calendar) rows() []agendaRow {
	var rows []agendaRow
	today := command.Today()
	for offset := range calendarDays {
		day := s.start.AddDate(0, 0, offset)
		var events []*api.Value
		for i := range s.events {
			if onDay(s.events[i], day) {
				events = append(events, &s.events[i])
			}
		}
		if len(events) == 0 && !day.Equal(today) {
			continue
		}
		rows = append(rows, agendaRow{day: day})
		for _, event := range events {
			rows = append(rows, agendaRow{day, event})
		}
	}
	return rows
}

func (s *Calendar) Draw(b *Buffer, area Rect, view *View) {
	end := s.start.AddDate(0, 0, calendarDays-1)
	title := toolIcon("calendar") + " " + s.tool.Get("name").S() + " · " + s.start.Format("2 Jan") + " – " + end.Format("2 Jan")
	rows := s.rows()
	now := time.Now()
	today := command.Today()

	items := make([]ListItem, len(rows))
	for i, row := range rows {
		if row.event == nil {
			label, style := row.day.Format("Monday 2 January"), bold()
			if row.day.Equal(today) {
				label, style = "Today · "+label, Style{}.Fg(accent()).With(Bold)
			}
			lines := []Line{RawLine(""), StyledLine(label, style)}
			if row.day.Equal(today) && !slices.ContainsFunc(rows, func(other agendaRow) bool { return other.day.Equal(row.day) && other.event != nil }) {
				lines = append(lines, StyledLine("  Nothing today. Free as a bird 🐦", dim()))
			}
			items[i] = Item(lines...)
			continue
		}
		event := *row.event
		allDay := event.Get("all_day").Truthy()
		timeText := "all day    "
		if !allDay {
			timeText = runeSlice(event.Get("starts_at").S(), 11, 16) + "–" + runeSlice(event.Get("ends_at").S(), 11, 16)
		}
		happening := false
		if !allDay {
			from, okFrom := local(event.Get("starts_at"))
			till, okTill := local(event.Get("ends_at"))
			happening = okFrom && okTill && !from.After(now) && now.Before(till)
		}
		timeStyle := dim()
		if happening {
			timeStyle = Style{}.Fg(success()).With(Bold)
		}
		spans := []Span{Styled("  "+timeText+"  ", timeStyle), Styled(event.Get("summary").S(), bold())}
		if calendar := event.Get("calendar", "name"); !calendar.IsNull() {
			spans = append(spans, Styled("  "+calendar.S(), Style{}.Fg(personColor(calendar.S()))))
		}
		if location := event.Get("location").S(); location != "" {
			spans = append(spans, Styled("  📍 "+location, dim()))
		}
		if event.Get("recurring").Truthy() {
			spans = append(spans, Styled("  🔁", dim()))
		}
		if happening {
			spans = append(spans, Styled("  ● now", Style{}.Fg(success())))
		}
		items[i] = Item(LineOf(spans...))
	}

	block := panel(title, true)
	if s.local {
		bottom := StyledLine(" kept in Dobase ", dim()).RightAligned()
		block.TitleBottom = &bottom
	}
	s.selected = min(s.selected, sat(len(rows)-1))
	List{Items: items, Block: block, Highlight: Style{}.With(Reversed)}.Render(b, area, s.selected)
}

// runeSlice is the characters from..to of text (fewer when it's shorter).
func runeSlice(text string, from, to int) string {
	runes := []rune(text)
	from, to = min(from, len(runes)), min(to, len(runes))
	return string(runes[from:to])
}

// shiftCalendar is a job showing the two weeks from start moved by days.
func shiftCalendar(tool api.Value, start time.Time, days int) Job {
	return func(app *App) error {
		start := start.AddDate(0, 0, days)
		fresh, err := loadCalendarFrom(app, tool, start)
		if err != nil {
			return err
		}
		if calendar, ok := app.screen.(*Calendar); ok {
			if days == 0 {
				fresh.selected = calendar.selected
			}
			app.screen = fresh
		}
		return nil
	}
}

// onDay says whether event takes place on day (it may span several).
func onDay(event api.Value, day time.Time) bool {
	starts, ok := command.ParseDate(runeSlice(event.Get("starts_at").S(), 0, 10))
	if !ok {
		return false
	}
	ends, ok := command.ParseDate(runeSlice(event.Get("ends_at").S(), 0, 10))
	if !ok {
		return false
	}
	// Something that ends at midnight is over before that day begins.
	if endsAt := event.Get("ends_at").S(); ends.After(starts) && len(endsAt) >= 16 && endsAt[11:16] == "00:00" {
		ends = ends.AddDate(0, 0, -1)
	}
	if ends.Before(starts) {
		ends = starts
	}
	return !starts.After(day) && !day.After(ends)
}
