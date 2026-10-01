package tui

import (
	"strings"
	"testing"

	"github.com/gdamore/tcell/v2"
)

// styleAt is the style of the first cell of text on screen.
func (h *harness) styleAt(text string) tcell.Style {
	h.t.Helper()
	for y, row := range strings.Split(h.text(), "\n") {
		if before, _, found := strings.Cut(row, text); found {
			_, style, _ := h.screen.Get(textWidth(before), y)
			return style
		}
	}
	h.t.Fatalf("the screen doesn't show %q", text)
	return tcell.StyleDefault
}

func TestTheSelectedRowIsReversedWhenThereIsNoColor(t *testing.T) {
	detected := colorDepth
	t.Cleanup(func() { colorDepth = detected })

	for _, c := range []struct {
		depth    depth
		reversed bool
	}{{depthNone, true}, {depthIndexed, false}} {
		colorDepth = func() depth { return c.depth }
		h := newHarness(t)
		h.char('1')
		_, background, attributes := h.styleAt("Water plants").Decompose()
		if reversed := attributes&tcell.AttrReverse != 0; reversed != c.reversed {
			t.Errorf("depth %d: reversed is %v", c.depth, reversed)
		}
		if colored := background != tcell.ColorDefault && background != tcell.ColorReset; colored == c.reversed {
			t.Errorf("depth %d: the background is %v", c.depth, background)
		}
	}
}
