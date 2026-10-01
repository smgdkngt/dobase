package tui

// Colors, the logo and the little bits of personality.

import (
	"fmt"
	"math"
	"os"
	"strings"
	"sync"

	"github.com/gdamore/tcell/v2"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

var logoLines = [5]string{
	`     _       _                    `,
	`  __| | ___ | |__   __ _ ___  ___ `,
	` / _` + "`" + ` |/ _ \| '_ \ / _` + "`" + ` / __|/ _ \`,
	`| (_| | (_) | |_) | (_| \__ \  __/`,
	` \__,_|\___/|_.__/ \__,_|___/\___|`,
}

type depth int

const (
	depthNone depth = iota
	depthIndexed
	depthTrue
)

// colorDepth: NO_COLOR turns colors off; terminals that don't say they do
// 24-bit color get the 256-color palette.
var colorDepth = sync.OnceValue(func() depth {
	if os.Getenv("NO_COLOR") != "" {
		return depthNone
	}
	if term := os.Getenv("COLORTERM"); strings.Contains(term, "truecolor") || strings.Contains(term, "24bit") {
		return depthTrue
	}
	return depthIndexed
})

func rgb(r, g, b uint8) tcell.Color {
	switch colorDepth() {
	case depthNone:
		return tcell.ColorReset
	case depthTrue:
		return tcell.NewRGBColor(int32(r), int32(g), int32(b))
	}
	level := func(value uint8) int {
		switch {
		case value < 48:
			return 0
		case value < 115:
			return 1
		}
		return int(value-35) / 40
	}
	return tcell.PaletteColor(16 + 36*level(r) + 6*level(g) + level(b))
}

type tone = [3]uint8

// palette is the colours the app draws in. They are Dobase's own until the
// person's theme arrives (wearTheme), and then that theme's: the same palette
// the web app is in, so on an Omarchy desktop the two match the terminal.
type palette struct {
	accent, onAccent, muted, success, warning, danger tone
	// What the logo's gradient runs between
	logoFrom, logoTo tone
	cards            map[string]tone
}

var ownPalette = palette{
	accent: tone{59, 130, 246}, onAccent: tone{255, 255, 255}, muted: tone{128, 128, 140},
	success: tone{34, 197, 94}, warning: tone{245, 158, 11}, danger: tone{239, 68, 68},
	logoFrom: tone{59, 130, 246}, logoTo: tone{236, 72, 153},
	cards: map[string]tone{
		"red": {239, 68, 68}, "orange": {249, 115, 22}, "yellow": {234, 179, 8},
		"green": {34, 197, 94}, "blue": {59, 130, 246}, "purple": {168, 85, 247},
	},
}

// wearing is only touched on the event loop: at the start and when a refresh
// brings another theme.
var wearing = ownPalette

// wearTheme takes the colours of what GET /appearance answers. Without a theme,
// or from a server that doesn't have them yet, the app keeps its own.
func wearTheme(appearance api.Value) {
	theme := appearance.Get("colors")
	read := func(name string, fallback tone) tone {
		if color, ok := parseHex(theme.Get(name).S()); ok {
			return color
		}
		return fallback
	}
	accent, hasAccent := parseHex(theme.Get("accent").S())
	if !hasAccent {
		wearing = ownPalette
		return
	}

	next := palette{
		accent:   accent,
		onAccent: readableOn(accent, read("background", tone{0, 0, 0})),
		muted:    ownPalette.muted,
		success:  read("green", ownPalette.success),
		warning:  read("yellow", ownPalette.warning),
		danger:   read("red", ownPalette.danger),
		logoFrom: accent,
		logoTo:   read("magenta", ownPalette.logoTo),
		cards: map[string]tone{
			"red": read("red", ownPalette.cards["red"]), "orange": read("orange", read("yellow", ownPalette.cards["orange"])),
			"yellow": read("yellow", ownPalette.cards["yellow"]), "green": read("green", ownPalette.cards["green"]),
			"blue": read("blue", ownPalette.cards["blue"]), "purple": read("magenta", ownPalette.cards["purple"]),
		},
	}
	background, hasBackground := parseHex(theme.Get("background").S())
	foreground, hasForeground := parseHex(theme.Get("foreground").S())
	if hasBackground && hasForeground {
		next.muted = mixTone(foreground, background, 0.45)
	}
	wearing = next
}

func parseHex(text string) (tone, bool) {
	var color tone
	if len(text) != 7 || text[0] != '#' {
		return color, false
	}
	if _, err := fmt.Sscanf(text[1:], "%02x%02x%02x", &color[0], &color[1], &color[2]); err != nil {
		return color, false
	}
	return color, true
}

func mixTone(from, to tone, amount float32) tone {
	var mixed tone
	for i := range mixed {
		mixed[i] = uint8(float32(from[i]) + (float32(to[i])-float32(from[i]))*amount)
	}
	return mixed
}

// luminance is how light a colour looks, 0 to 1 (WCAG).
func luminance(color tone) float64 {
	channel := func(value uint8) float64 {
		v := float64(value) / 255
		if v <= 0.03928 {
			return v / 12.92
		}
		return math.Pow((v+0.055)/1.055, 2.4)
	}
	return 0.2126*channel(color[0]) + 0.7152*channel(color[1]) + 0.0722*channel(color[2])
}

// readableOn is what to write in on a fill: white, or the theme's dark
// background when that reads better (a pastel accent).
func readableOn(fill, dark tone) tone {
	contrast := func(a, b tone) float64 {
		lighter, darker := math.Max(luminance(a), luminance(b)), math.Min(luminance(a), luminance(b))
		return (lighter + 0.05) / (darker + 0.05)
	}
	white := tone{255, 255, 255}
	if contrast(dark, fill) > contrast(white, fill) {
		return dark
	}
	return white
}

func paint(color tone) tcell.Color { return rgb(color[0], color[1], color[2]) }

func accent() tcell.Color  { return paint(wearing.accent) }
func muted() tcell.Color   { return paint(wearing.muted) }
func success() tcell.Color { return paint(wearing.success) }
func warning() tcell.Color { return paint(wearing.warning) }
func danger() tcell.Color  { return paint(wearing.danger) }

func dim() Style  { return Style{}.Fg(muted()) }
func bold() Style { return Style{}.With(Bold) }

// selected is the selected row: on the accent color, in whatever reads on it, or
// reversed when there's no color to show it with.
func selected() Style {
	if colorDepth() == depthNone {
		return Style{}.With(Reversed | Bold)
	}
	return Style{}.Bg(accent()).Fg(paint(wearing.onAccent)).With(Bold)
}

// cardColor is a card's color, as the app names them.
func cardColor(name string) (tcell.Color, bool) {
	if color, ok := wearing.cards[name]; ok {
		return paint(color), true
	}
	return 0, false
}

// personColor is a steady color per person, so a chat reads at a glance.
func personColor(name string) tcell.Color {
	palette := [8][3]uint8{{96, 165, 250}, {244, 114, 182}, {52, 211, 153}, {251, 191, 36}, {167, 139, 250}, {248, 113, 113}, {45, 212, 191}, {251, 146, 60}}
	hash := uint32(7)
	for i := 0; i < len(name); i++ {
		hash = hash*31 + uint32(name[i])
	}
	c := palette[hash%uint32(len(palette))]
	return rgb(c[0], c[1], c[2])
}

// logo is the logo in a gradient (blue to pink, or the theme's accent to its
// magenta) that drifts slowly with tick.
func logo(tick uint64) []Line {
	width := float32(len([]rune(logoLines[0])))
	lines := make([]Line, len(logoLines))
	for row, text := range logoLines {
		var spans []Span
		for column, char := range []rune(text) {
			phase := (float32(column)+float32(row)*2)/width + float32(tick)/40
			phase -= float32(math.Floor(float64(phase)))
			wave := phase * 2
			if phase >= 0.5 {
				wave = (1 - phase) * 2
			}
			color := paint(mixTone(wearing.logoFrom, wearing.logoTo, wave))
			spans = append(spans, Styled(string(char), Style{}.Fg(color).With(Bold)))
		}
		lines[row] = LineOf(spans...)
	}
	return lines
}

func toolIcon(kind string) string {
	switch kind {
	case "boards":
		return "📋"
	case "todos":
		return "✅"
	case "docs":
		return "📝"
	case "chat":
		return "💬"
	case "files":
		return "📁"
	case "mail":
		return "📬"
	case "calendar":
		return "📅"
	case "room":
		return "🎥"
	}
	return "🧰"
}

func greeting(hour int, name string) string {
	hello, emoji := "Burning the midnight oil", "🦉"
	switch {
	case hour >= 5 && hour <= 11:
		hello, emoji = "Good morning", "🌅"
	case hour >= 12 && hour <= 17:
		hello, emoji = "Good afternoon", "🌞"
	case hour >= 18 && hour <= 22:
		hello, emoji = "Good evening", "🌙"
	}
	return fmt.Sprintf("%s, %s %s", hello, name, emoji)
}

// cheers are said when something gets done.
var cheers = [8]string{
	"Nice one! 🎉",
	"Done and dusted ✨",
	"Look at you go 🚀",
	"Another one bites the dust 💪",
	"Shipped! 🚢",
	"Crushing it 🔥",
	"Tick! ✔",
	"High five 🙌",
}

var tips = [7]string{
	"Press / to search everything you share.",
	"Press ? any time to see the keys.",
	"Press o to open what you're looking at in the browser.",
	"Press ] and [ to hop between tools.",
	"On a board, H and L move a card to the next column.",
	"In a todo list, space ticks a todo off.",
	"Scripts and Claude can use the same tool: dobase help.",
}

// isDoneColumn: a column where finished work goes, which earns confetti.
func isDoneColumn(name string) bool {
	name = strings.ToLower(name)
	for _, word := range []string{"done", "shipped", "klaar", "finished", "complete", "live"} {
		if strings.Contains(name, word) {
			return true
		}
	}
	return false
}
