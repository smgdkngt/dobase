package tui

// Colors, the logo and the little bits of personality.

import (
	"fmt"
	"math"
	"os"
	"strings"
	"sync"

	"github.com/gdamore/tcell/v2"
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

func accent() tcell.Color  { return rgb(59, 130, 246) }
func muted() tcell.Color   { return rgb(128, 128, 140) }
func success() tcell.Color { return rgb(34, 197, 94) }
func warning() tcell.Color { return rgb(245, 158, 11) }
func danger() tcell.Color  { return rgb(239, 68, 68) }

func dim() Style  { return Style{}.Fg(muted()) }
func bold() Style { return Style{}.With(Bold) }

// selected is the selected row: white on the accent color, or reversed when
// there's no color to show it with.
func selected() Style {
	if colorDepth() == depthNone {
		return Style{}.With(Reversed | Bold)
	}
	return Style{}.Bg(accent()).Fg(tcell.ColorWhite).With(Bold)
}

// cardColor is a card's color, as the app names them.
func cardColor(name string) (tcell.Color, bool) {
	switch name {
	case "red":
		return rgb(239, 68, 68), true
	case "orange":
		return rgb(249, 115, 22), true
	case "yellow":
		return rgb(234, 179, 8), true
	case "green":
		return rgb(34, 197, 94), true
	case "blue":
		return rgb(59, 130, 246), true
	case "purple":
		return rgb(168, 85, 247), true
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

// logo is the logo in a blue-to-pink gradient that drifts slowly with tick.
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
			mix := func(from, to float32) uint8 { return uint8(from + (to-from)*wave) }
			color := rgb(mix(59, 236), mix(130, 72), mix(246, 153))
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
