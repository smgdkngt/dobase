package tui

// A video room, which only works in the browser.

import "github.com/smgdkngt/dobase/cli/internal/api"

var camera = [7]string{
	".-------------------.    ",
	"|  .-----------.    |==. ",
	"|  |           |    |  | ",
	"|  |   (•‿•)   |    |==' ",
	"|  |           |    |    ",
	"|  '-----------'    |    ",
	"'-------------------'    ",
}

type Room struct {
	notLive
	tool api.Value
}

func (s *Room) Tool() (api.Value, bool)  { return s.tool, true }
func (s *Room) Key(Key, *View, *Fx) bool { return false }
func (s *Room) Refresh() Job             { return nil }
func (s *Room) Hints() []hint            { return []hint{{"o", "open in browser"}, {"esc", "home"}} }
func (s *Room) Help() []hint             { return []hint{{"o", "Open the room in your browser"}} }

func (s *Room) Draw(b *Buffer, area Rect, view *View) {
	block := panel(toolIcon("room")+" "+s.tool.Get("name").S(), true)
	inner := block.Inner(area)
	block.Render(b, area)
	var lines []Line
	for _, line := range camera {
		lines = append(lines, StyledLine(line, dim()))
	}
	lines = append(lines,
		RawLine(""),
		StyledLine("Rooms need a camera, so they live in the browser.", bold()),
		StyledLine("Press o to join. Don't forget to fix your hair 💇", dim()))
	height := min(len(lines), inner.H)
	spot := Rect{inner.X, inner.Y + (inner.H-height+1)/2, inner.W, height}
	Paragraph{Lines: lines, Align: AlignCenter}.Render(b, spot)
}
