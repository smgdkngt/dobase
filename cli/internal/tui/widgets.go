package tui

// Small pieces the screens share: keys, a text field, confetti, popups and key hints.

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/rivo/uniseg"
	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

// -- Keys ---------------------------------------------------------------------------

type KeyCode int

const (
	KeyRune KeyCode = iota
	KeyEnter
	KeyEsc
	KeyTab
	KeyBackTab
	KeyBackspace
	KeyDelete
	KeyLeft
	KeyRight
	KeyUp
	KeyDown
	KeyHome
	KeyEnd
	KeyPageUp
	KeyPageDown
	KeyOther
)

// Key is a key press: a code, or a character (with Ctrl or not).
type Key struct {
	Code KeyCode
	Rune rune
	Ctrl bool
}

// Is says whether the key is this character, whatever the modifiers.
func (k Key) Is(chars ...rune) bool {
	if k.Code != KeyRune {
		return false
	}
	for _, char := range chars {
		if k.Rune == char {
			return true
		}
	}
	return false
}

// OneOf says whether the key has one of these codes.
func (k Key) OneOf(codes ...KeyCode) bool {
	for _, code := range codes {
		if k.Code == code {
			return true
		}
	}
	return false
}

// hint is a key and what it does, for the bottom bar and the help popup.
type hint struct{ key, action string }

// -- A text field -------------------------------------------------------------------

// TextInput is a one-line text field.
type TextInput struct {
	chars  []rune
	cursor int
}

// textInputWith is a field that starts with text, the cursor at its end.
func textInputWith(text string) TextInput {
	chars := []rune(text)
	return TextInput{chars: chars, cursor: len(chars)}
}

func (t *TextInput) Text() string { return string(t.chars) }

func (t *TextInput) IsBlank() bool {
	for _, char := range t.chars {
		if !unicode.IsSpace(char) {
			return false
		}
	}
	return true
}

func (t *TextInput) Clear() {
	t.chars = nil
	t.cursor = 0
}

// Key handles editing keys; it returns false for keys it leaves to the caller (Enter, Esc, ...).
func (t *TextInput) Key(key Key) bool {
	switch {
	case key.Code == KeyRune && key.Ctrl && key.Rune == 'u':
		t.chars = append([]rune{}, t.chars[t.cursor:]...)
		t.cursor = 0
	case key.Code == KeyRune && key.Ctrl && key.Rune == 'w':
		start := t.cursor
		for start > 0 && t.chars[start-1] == ' ' {
			start--
		}
		for start > 0 && t.chars[start-1] != ' ' {
			start--
		}
		t.chars = append(t.chars[:start:start], t.chars[t.cursor:]...)
		t.cursor = start
	case key.Code == KeyRune && key.Ctrl && key.Rune == 'a':
		t.cursor = 0
	case key.Code == KeyRune && key.Ctrl && key.Rune == 'e':
		t.cursor = len(t.chars)
	case key.Code == KeyRune && !key.Ctrl:
		t.chars = append(t.chars[:t.cursor:t.cursor], append([]rune{key.Rune}, t.chars[t.cursor:]...)...)
		t.cursor++
	case key.Code == KeyBackspace:
		if t.cursor > 0 {
			t.cursor--
			t.chars = append(t.chars[:t.cursor:t.cursor], t.chars[t.cursor+1:]...)
		}
	case key.Code == KeyDelete:
		if t.cursor < len(t.chars) {
			t.chars = append(t.chars[:t.cursor:t.cursor], t.chars[t.cursor+1:]...)
		}
	case key.Code == KeyLeft:
		t.cursor = max(t.cursor-1, 0)
	case key.Code == KeyRight:
		t.cursor = min(t.cursor+1, len(t.chars))
	case key.Code == KeyHome:
		t.cursor = 0
	case key.Code == KeyEnd:
		t.cursor = len(t.chars)
	default:
		return false
	}
	return true
}

// Render draws the text in area (one line), scrolled so the cursor shows, and places the cursor.
func (t *TextInput) Render(b *Buffer, area Rect, placeholder string, focused bool) {
	// The text starts as far left as leaves the cursor a cell in the field.
	start, room := t.cursor, sat(area.W-1)
	for start > 0 && textWidth(string(t.chars[start-1])) <= room {
		start--
		room -= textWidth(string(t.chars[start]))
	}
	if len(t.chars) == 0 && placeholder != "" {
		b.RenderLine(StyledLine(placeholder, dim()), area)
	} else {
		b.RenderLine(RawLine(string(t.chars[start:])), area)
	}
	if focused {
		offset := textWidth(string(t.chars[start:t.cursor]))
		b.SetCursor(area.X+min(offset, sat(area.W-1)), area.Y)
	}
}

// -- Confetti -----------------------------------------------------------------------

const confettiLength = 1400 * time.Millisecond

// Confetti is a short burst over the screen when something gets done.
type Confetti struct {
	started time.Time
	seed    uint64
}

func newConfetti(seed uint64) *Confetti { return &Confetti{started: time.Now(), seed: seed} }

func (c *Confetti) finished() bool { return time.Since(c.started) > confettiLength }

func (c *Confetti) Render(b *Buffer, area Rect) {
	if area.W < 4 || area.H < 4 {
		return
	}
	progress := float32(time.Since(c.started).Seconds()) / float32(confettiLength.Seconds())
	colors := [6][3]uint8{{239, 68, 68}, {234, 179, 8}, {34, 197, 94}, {59, 130, 246}, {168, 85, 247}, {236, 72, 153}}
	pieces := []string{"✦", "•", "*", "▪", "✧", "◆", "~"}
	state := c.seed | 1
	next := func() uint64 {
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		return state
	}

	width, height := uint64(area.W), uint64(area.H)
	for range min(area.W*2, 160) {
		x := next() % width
		speed := 0.6 + float32(next()%100)/100
		drift := int(next()%7) - 3
		startRow := float32(next()%(height/2)) - float32(area.H)/2
		row := startRow + progress*speed*float32(area.H)*1.4
		column := int(x) + int(float32(drift)*progress*3)
		if row < 0 || row >= float32(area.H) || column < 0 || column >= area.W {
			continue
		}
		color := colors[next()%uint64(len(colors))]
		piece := pieces[next()%uint64(len(pieces))]
		if cell := b.at(area.X+column, area.Y+int(row)); cell != nil {
			cell.symbol = piece
			cell.setStyle(Style{}.Fg(rgb(color[0], color[1], color[2])).With(Bold))
		}
	}
}

// -- Frames and hints ---------------------------------------------------------------

// popup clears and frames a centered popup, returning the area inside the frame.
func popup(b *Buffer, title string, width, height int) Rect {
	screen := b.Area
	area := screen.Centered(min(width, sat(screen.W-2)), min(height, sat(screen.H-2)))
	b.Clear(area)
	titleLine := LineOf(Styled(" "+title+" ", bold()))
	block := Block{Border: Rounded, BorderStyle: Style{}.Fg(accent()), Title: &titleLine}
	block.Render(b, area)
	return block.Inner(area)
}

// hintsLine is "key action  key action" for the bottom bar.
func hintsLine(pairs []hint) Line {
	var spans []Span
	for index, pair := range pairs {
		if index > 0 {
			spans = append(spans, Styled("  ", dim()))
		}
		spans = append(spans, Styled(pair.key, Style{}.Fg(accent()).With(Bold)), Styled(" "+pair.action, dim()))
	}
	return LineOf(spans...)
}

// fitting is the hints that fit in width: the ones before the last (? help) go
// first, from the end.
func fitting(hints []hint, width int) []hint {
	for len(hints) > 1 && hintsLine(hints).Width() > width {
		hints = append(slices.Clone(hints[:len(hints)-2]), hints[len(hints)-1])
	}
	return hints
}

// panel is a rounded block with a title; highlighted when it has the focus.
func panel(title string, focused bool) *Block {
	color, style := muted(), Style{}
	if focused {
		color, style = accent(), bold()
	}
	line := LineOf(Styled(" "+title+" ", style))
	return &Block{Border: Rounded, BorderStyle: Style{}.Fg(color), Title: &line}
}

// -- Text ---------------------------------------------------------------------------

// wrap wraps text to width columns, keeping paragraphs.
func wrap(text string, width int) []string {
	width = max(width, 8)
	var lines []string
	for _, paragraph := range strings.Split(strings.TrimRightFunc(text, unicode.IsSpace), "\n") {
		line := ""
		for _, word := range strings.Split(paragraph, " ") {
			fits := textWidth(line+" "+word) <= width
			switch {
			case line == "":
				line = word
			case fits:
				line += " " + word
			default:
				lines = append(lines, line)
				line = word
			}
			for textWidth(line) > width {
				var head string
				head, line = cut(line, width)
				lines = append(lines, head)
			}
		}
		lines = append(lines, line)
	}
	return lines
}

// cut splits text after the characters that fit in width cells; the first one always goes along.
func cut(text string, width int) (string, string) {
	rest, used, state := text, 0, -1
	for rest != "" {
		cluster, after, _, next := uniseg.FirstGraphemeClusterInString(rest, state)
		cells := textWidth(cluster)
		if used > 0 && used+cells > width {
			break
		}
		used += cells
		rest, state = after, next
	}
	return text[:len(text)-len(rest)], rest
}

// padded is text with spaces after it up to width cells.
func padded(text string, width int) string {
	return text + strings.Repeat(" ", sat(width-textWidth(text)))
}

// truncate cuts text to width columns with an ellipsis.
func truncate(text string, width int) string {
	if textWidth(text) <= width {
		return text
	}
	var out strings.Builder
	for _, char := range text {
		if textWidth(out.String()+string(char)+"…") > width {
			break
		}
		out.WriteRune(char)
	}
	return out.String() + "…"
}

// splitLines splits text into lines as Rust's str::lines does.
func splitLines(text string) []string {
	if text == "" {
		return nil
	}
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	for i, line := range lines {
		lines[i] = strings.TrimSuffix(line, "\r")
	}
	return lines
}

// -- Times --------------------------------------------------------------------------

// local is a server timestamp in this computer's time zone.
func local(value api.Value) (time.Time, bool) {
	t, err := time.Parse(time.RFC3339Nano, value.S())
	if err != nil {
		return time.Time{}, false
	}
	return t.In(time.Local), true
}

// civil is the calendar date of t, as midnight UTC.
func civil(t time.Time) time.Time {
	year, month, day := t.Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

// ago is a server timestamp the way people say it: "just now", "12 min ago", "yesterday 14:05", "Sep 20".
func ago(value api.Value) string {
	then, ok := local(value)
	if !ok {
		return command.Moment(value)
	}
	now := time.Now()
	minutes := int64(now.Sub(then).Seconds()) / 60
	days := int(civil(now).Sub(civil(then)).Hours() / 24)
	switch {
	case minutes < 1:
		return "just now"
	case minutes < 60:
		return fmt.Sprintf("%d min ago", minutes)
	case days == 0:
		return "today " + then.Format("15:04")
	case days == 1:
		return "yesterday " + then.Format("15:04")
	case days >= 2 && days < 7:
		return then.Format("Monday 15:04")
	case then.Year() == now.Year():
		return then.Format("Jan 2")
	}
	return then.Format("Jan 2, 2006")
}

// dueDate reads a due date as people type it: today, tomorrow, a weekday (the
// next one), +3 (days from now), 2026-10-01, or none to clear it (nil).
func dueDate(text string) (*time.Time, error) {
	text = strings.ToLower(strings.TrimSpace(text))
	today := command.Today()
	days := func(count int64) *time.Time {
		date := today.AddDate(0, 0, int(count))
		return &date
	}
	prefix := ""
	if len(text) >= 3 && utf8.ValidString(text[:3]) {
		prefix = text[:3]
	}
	weekday := -1
	switch prefix {
	case "mon", "maa":
		weekday = 1
	case "tue", "din":
		weekday = 2
	case "wed", "woe":
		weekday = 3
	case "thu", "don":
		weekday = 4
	case "fri", "vri":
		weekday = 5
	case "sat", "zat":
		weekday = 6
	case "sun", "zon":
		weekday = 7
	}

	var date *time.Time
	switch {
	case text == "" || text == "none" || text == "-":
		return nil, nil
	case text == "today" || text == "vandaag":
		date = &today
	case text == "tomorrow" || text == "morgen":
		date = days(1)
	case text == "next week":
		date = days(7)
	case strings.HasPrefix(text, "+"):
		if count, err := strconv.ParseInt(strings.TrimRight(text[1:], "d"), 10, 64); err == nil {
			date = days(count)
		}
	case weekday > 0:
		current := (int(today.Weekday())+6)%7 + 1
		ahead := ((weekday-current)%7 + 7) % 7
		if ahead == 0 {
			ahead = 7
		}
		date = days(int64(ahead))
	default:
		if parsed, ok := command.ParseDate(text); ok {
			date = &parsed
		}
	}
	if date == nil {
		return nil, api.Usagef("“%s” isn't a date. Try fri, +3, tomorrow or 2026-10-01.", text)
	}
	return date, nil
}
