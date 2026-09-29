package tui

// The little drawing layer the screens use: a cell buffer with styles that
// patch like ratatui's, styled lines, paragraphs (wrapped or not), bordered
// blocks with titles, lists with a selection, and layout splits. Only what the
// screens need.

import (
	"math"
	"strings"
	"unicode"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/uniseg"
)

// -- Styles -----------------------------------------------------------------------

// Modifier is text decoration.
type Modifier uint8

const (
	Bold Modifier = 1 << iota
	Italic
	Underlined
	Reversed
	CrossedOut
)

// Style changes a cell's look; unset colors leave the cell's color as it is.
type Style struct {
	fg, bg       tcell.Color
	hasFg, hasBg bool
	add, sub     Modifier
}

func (s Style) Fg(color tcell.Color) Style {
	s.fg, s.hasFg = color, true
	return s
}

func (s Style) Bg(color tcell.Color) Style {
	s.bg, s.hasBg = color, true
	return s
}

// With adds modifiers.
func (s Style) With(modifier Modifier) Style {
	s.add |= modifier
	s.sub &^= modifier
	return s
}

// Patch lays other over s.
func (s Style) Patch(other Style) Style {
	if other.hasFg {
		s.fg, s.hasFg = other.fg, true
	}
	if other.hasBg {
		s.bg, s.hasBg = other.bg, true
	}
	s.add = (s.add &^ other.sub) | other.add
	s.sub = (s.sub &^ other.add) | other.sub
	return s
}

// -- Text -------------------------------------------------------------------------

type Align int

const (
	AlignNone Align = iota
	AlignLeft
	AlignCenter
	AlignRight
)

// Span is text in one style.
type Span struct {
	Text  string
	Style Style
}

func Raw(text string) Span                     { return Span{Text: text} }
func Styled(text string, style Style) Span     { return Span{Text: text, Style: style} }
func (s Span) Width() int                      { return textWidth(s.Text) }
func LineOf(spans ...Span) Line                { return Line{Spans: spans} }
func RawLine(text string) Line                 { return Line{Spans: []Span{{Text: text}}} }
func StyledLine(text string, style Style) Line { return LineOf(Styled(text, style)) }

// Line is spans on one row.
type Line struct {
	Spans []Span
	Style Style
	Align Align
}

func (l Line) Width() int {
	width := 0
	for _, span := range l.Spans {
		width += span.Width()
	}
	return width
}

func (l Line) Centered() Line     { l.Align = AlignCenter; return l }
func (l Line) RightAligned() Line { l.Align = AlignRight; return l }

// Text is the line as plain text.
func (l Line) Text() string {
	var text strings.Builder
	for _, span := range l.Spans {
		text.WriteString(span.Text)
	}
	return text.String()
}

type grapheme struct {
	symbol string
	width  int
	style  Style
}

// graphemes splits text into what goes in cells, dropping control characters.
func graphemes(text string, style Style) []grapheme {
	var out []grapheme
	state := -1
	for text != "" {
		var cluster string
		var width int
		cluster, text, width, state = uniseg.FirstGraphemeClusterInString(text, state)
		if strings.IndexFunc(cluster, unicode.IsControl) >= 0 {
			continue
		}
		if len(cluster) == 1 {
			width = 1
		}
		out = append(out, grapheme{cluster, width, style})
	}
	return out
}

// textWidth is how many cells text takes, measured as ratatui measures spans
// and lines: a control character counts as one cell, though it isn't drawn.
func textWidth(text string) int {
	width, state := 0, -1
	for text != "" {
		var cluster string
		var cells int
		cluster, text, cells, state = uniseg.FirstGraphemeClusterInString(text, state)
		if len(cluster) == 1 || strings.IndexFunc(cluster, unicode.IsControl) >= 0 {
			cells = 1
		}
		width += cells
	}
	return width
}

func (l Line) graphemes(base Style) []grapheme {
	var out []grapheme
	lineStyle := base.Patch(l.Style)
	for _, span := range l.Spans {
		out = append(out, graphemes(span.Text, lineStyle.Patch(span.Style))...)
	}
	return out
}

// -- Areas ------------------------------------------------------------------------

type Rect struct{ X, Y, W, H int }

func (r Rect) Right() int     { return r.X + r.W }
func (r Rect) Bottom() int    { return r.Y + r.H }
func (r Rect) Empty() bool    { return r.W <= 0 || r.H <= 0 }
func sat(n int) int           { return max(n, 0) }
func (r Rect) Row(y int) Rect { return Rect{r.X, y, r.W, 1} }

// Inner shrinks the area by a margin on each side.
func (r Rect) Inner(horizontal, vertical int) Rect {
	if r.W < 2*horizontal || r.H < 2*vertical {
		return Rect{r.X, r.Y, 0, 0}
	}
	return Rect{r.X + horizontal, r.Y + vertical, r.W - 2*horizontal, r.H - 2*vertical}
}

func (r Rect) intersect(other Rect) Rect {
	x, y := max(r.X, other.X), max(r.Y, other.Y)
	right, bottom := min(r.Right(), other.Right()), min(r.Bottom(), other.Bottom())
	return Rect{x, y, sat(right - x), sat(bottom - y)}
}

// Centered is a width × height area in the middle of r (rounding the offsets up, as ratatui does).
func (r Rect) Centered(width, height int) Rect {
	width, height = min(width, r.W), min(height, r.H)
	return Rect{r.X + (r.W-width+1)/2, r.Y + (r.H-height+1)/2, width, height}
}

// Constraint sizes one part of a split.
type Constraint struct {
	kind  int // length, min, percentage, fill
	value int
}

func Length(n int) Constraint     { return Constraint{0, n} }
func Min(n int) Constraint        { return Constraint{1, n} }
func Percentage(n int) Constraint { return Constraint{2, n} }

// splitVertical cuts rows: lengths are fixed and the Min part takes the rest.
func splitVertical(area Rect, constraints ...Constraint) []Rect {
	fixed := 0
	for _, c := range constraints {
		if c.kind == 0 {
			fixed += c.value
		}
	}
	rest := sat(area.H - fixed)
	out := make([]Rect, len(constraints))
	y := area.Y
	for i, c := range constraints {
		height := c.value
		if c.kind == 1 {
			height = max(rest, c.value)
		}
		height = min(height, sat(area.Bottom()-y))
		out[i] = Rect{area.X, y, area.W, height}
		y += height
	}
	return out
}

// splitPercentages cuts two columns with a gap of one, as ratatui does: the first
// gets its share of the whole width, rounded; the second what's left.
func splitPercentages(area Rect, first int) (Rect, Rect) {
	left := min(int(math.Floor(float64(area.W)*float64(first)/100+0.5)), area.W)
	right := sat(area.W - left - 1)
	return Rect{area.X, area.Y, left, area.H}, Rect{area.X + left + 1, area.Y, right, area.H}
}

// splitEqual cuts n equal columns with gaps of one, rounding the edges like ratatui.
func splitEqual(area Rect, n int) []Rect {
	size := float64(area.W-(n-1)) / float64(n)
	round := func(x float64) int { return int(math.Floor(x + 0.5)) }
	out := make([]Rect, n)
	for i := range out {
		start := float64(i) * (size + 1)
		from, to := round(start), round(start+size)
		out[i] = Rect{area.X + from, area.Y, sat(to - from), area.H}
	}
	return out
}

// -- The buffer -------------------------------------------------------------------

type cell struct {
	symbol string
	fg, bg tcell.Color
	mod    Modifier
}

func (c *cell) reset() { *c = cell{symbol: " "} }

func (c *cell) setStyle(style Style) {
	if style.hasFg {
		c.fg = style.fg
	}
	if style.hasBg {
		c.bg = style.bg
	}
	c.mod = (c.mod | style.add) &^ style.sub
}

// Buffer is a frame being drawn.
type Buffer struct {
	Area   Rect
	cells  []cell
	cursor *[2]int
}

func NewBuffer(width, height int) *Buffer {
	buffer := &Buffer{Area: Rect{0, 0, width, height}, cells: make([]cell, width*height)}
	for i := range buffer.cells {
		buffer.cells[i].reset()
	}
	return buffer
}

func (b *Buffer) at(x, y int) *cell {
	if x < b.Area.X || y < b.Area.Y || x >= b.Area.Right() || y >= b.Area.Bottom() {
		return nil
	}
	return &b.cells[y*b.Area.W+x]
}

// SetCursor shows the cursor at x, y after this frame.
func (b *Buffer) SetCursor(x, y int) { b.cursor = &[2]int{x, y} }

// SetStyle patches every cell in area.
func (b *Buffer) SetStyle(area Rect, style Style) {
	area = area.intersect(b.Area)
	for y := area.Y; y < area.Bottom(); y++ {
		for x := area.X; x < area.Right(); x++ {
			b.at(x, y).setStyle(style)
		}
	}
}

// Clear resets area to blank cells.
func (b *Buffer) Clear(area Rect) {
	area = area.intersect(b.Area)
	for y := area.Y; y < area.Bottom(); y++ {
		for x := area.X; x < area.Right(); x++ {
			b.at(x, y).reset()
		}
	}
}

// put sets one grapheme, blanking the cells a wide one covers.
func (b *Buffer) put(x, y int, g grapheme) {
	c := b.at(x, y)
	if c == nil {
		return
	}
	c.symbol = g.symbol
	c.setStyle(g.style)
	for hidden := x + 1; hidden < x+g.width; hidden++ {
		if c := b.at(hidden, y); c != nil {
			c.reset()
		}
	}
}

// SetString writes text from x, y, cut at maxWidth cells.
func (b *Buffer) SetString(x, y int, text string, maxWidth int, style Style) {
	remaining := min(sat(b.Area.Right()-x), maxWidth)
	for _, g := range graphemes(text, style) {
		if g.width == 0 {
			continue
		}
		if g.width > remaining {
			break
		}
		remaining -= g.width
		b.put(x, y, g)
		x += g.width
	}
}

// renderSpans draws spans in a row of area, after skipping skip cells. Each
// span takes its measured width, as in ratatui.
func (b *Buffer) renderSpans(spans []Span, area Rect, skip int) {
	x := area.X
	for _, span := range spans {
		width := textWidth(span.Text)
		if skip >= width {
			skip -= width
			continue
		}
		gs := graphemes(span.Text, span.Style)
		if skip > 0 {
			// Cut the start of the span; a wide character cut in half leaves a gap.
			available := width - skip
			for len(gs) > 0 && width > available {
				width -= gs[0].width
				gs = gs[1:]
			}
			x += available - width
			skip = 0
		}
		if x >= area.Right() {
			return
		}
		at := x
		for _, g := range gs {
			if g.width == 0 {
				continue
			}
			if at+g.width > area.Right() {
				break
			}
			b.put(at, area.Y, g)
			at += g.width
		}
		x += width
	}
}

// RenderLine draws a line in the first row of area, as ratatui's Line widget does:
// its style fills the row, and it's aligned (or cut) within it.
func (b *Buffer) RenderLine(line Line, area Rect) {
	b.renderLine(line, area, AlignNone)
}

func (b *Buffer) renderLine(line Line, area Rect, parent Align) {
	area = area.intersect(b.Area)
	if area.Empty() {
		return
	}
	area.H = 1
	width := line.Width()
	if width == 0 {
		return
	}
	b.SetStyle(area, line.Style)
	align := line.Align
	if align == AlignNone {
		align = parent
	}
	spans := make([]Span, len(line.Spans))
	for i, span := range line.Spans {
		spans[i] = Span{span.Text, line.Style.Patch(span.Style)}
	}
	if width <= area.W {
		indent := 0
		switch align {
		case AlignCenter:
			indent = (area.W - width) / 2
		case AlignRight:
			indent = area.W - width
		}
		b.renderSpans(spans, Rect{area.X + indent, area.Y, area.W - indent, 1}, 0)
		return
	}
	skip := 0
	switch align {
	case AlignCenter:
		skip = (width - area.W) / 2
	case AlignRight:
		skip = width - area.W
	}
	b.renderSpans(spans, area, skip)
}

// RenderSpan draws one span at the start of area.
func (b *Buffer) RenderSpan(span Span, area Rect) { b.RenderLine(LineOf(span), area) }

// RenderText draws lines one per row, like ratatui's Text widget.
func (b *Buffer) RenderText(lines []Line, area Rect) {
	for i, line := range lines {
		if i >= area.H {
			break
		}
		b.renderLine(line, Rect{area.X, area.Y + i, area.W, 1}, AlignNone)
	}
}

// -- Blocks -----------------------------------------------------------------------

type BorderType int

const (
	Rounded BorderType = iota
	Thick
)

// Block is a border with titles.
type Block struct {
	Border      BorderType
	BorderStyle Style
	Title       *Line
	TitleBottom *Line
}

func (Block) Inner(area Rect) Rect { return area.Inner(1, 1) }

func (bl Block) Render(b *Buffer, area Rect) {
	area = area.intersect(b.Area)
	if area.Empty() {
		return
	}
	symbols := [6]string{"╭", "╮", "╰", "╯", "─", "│"}
	if bl.Border == Thick {
		symbols = [6]string{"┏", "┓", "┗", "┛", "━", "┃"}
	}
	right, bottom := area.Right()-1, area.Bottom()-1
	set := func(x, y int, symbol string) {
		if c := b.at(x, y); c != nil {
			c.symbol = symbol
			c.setStyle(bl.BorderStyle)
		}
	}
	for y := area.Y + 1; y < bottom; y++ {
		set(area.X, y, symbols[5])
		set(right, y, symbols[5])
	}
	for x := area.X + 1; x < right; x++ {
		set(x, area.Y, symbols[4])
		set(x, bottom, symbols[4])
	}
	set(area.X, area.Y, symbols[0])
	set(right, area.Y, symbols[1])
	set(area.X, bottom, symbols[2])
	set(right, bottom, symbols[3])

	titles := Rect{area.X + 1, area.Y, sat(area.W - 2), 1}
	for _, title := range []*Line{bl.Title, bl.TitleBottom} {
		if title != nil && !titles.Empty() {
			width := title.Width()
			spot := Rect{titles.X, titles.Y, min(width, titles.W), 1}
			if title.Align == AlignRight {
				spot.X = max(titles.Right()-width, titles.X)
			}
			b.RenderLine(*title, spot)
		}
		titles.Y = bottom
	}
}

// -- Paragraphs -------------------------------------------------------------------

// Paragraph is text in an area, cut or wrapped at its edge.
type Paragraph struct {
	Lines  []Line
	Style  Style
	Block  *Block
	Wrap   bool
	Trim   bool
	Scroll int
	Align  Align
}

func (p Paragraph) Render(b *Buffer, area Rect) {
	area = area.intersect(b.Area)
	b.SetStyle(area, p.Style)
	if p.Block != nil {
		p.Block.Render(b, area)
		area = p.Block.Inner(area)
	}
	if area.Empty() {
		return
	}
	b.SetStyle(area, p.Style)

	type row struct {
		graphemes []grapheme
		align     Align
	}
	var rows []row
	for _, line := range p.Lines {
		align := line.Align
		if align == AlignNone {
			align = p.Align
		}
		gs := line.graphemes(Style{})
		if p.Wrap {
			for _, wrapped := range wordWrap(gs, area.W, p.Trim) {
				rows = append(rows, row{wrapped, align})
			}
		} else {
			var cut []grapheme
			width := 0
			for _, g := range gs {
				if g.width > area.W {
					continue
				}
				if width+g.width > area.W {
					break
				}
				width += g.width
				cut = append(cut, g)
			}
			rows = append(rows, row{cut, align})
		}
	}
	if p.Scroll >= len(rows) {
		return
	}
	for y, r := range rows[p.Scroll:] {
		if y >= area.H {
			break
		}
		width := 0
		for _, g := range r.graphemes {
			width += g.width
		}
		x := 0
		switch r.align {
		case AlignCenter:
			x = sat(area.W/2 - width/2)
		case AlignRight:
			x = sat(area.W - width)
		}
		for _, g := range r.graphemes {
			if g.width == 0 {
				continue
			}
			if c := b.at(area.X+x, area.Y+y); c != nil {
				c.symbol = g.symbol
				c.setStyle(g.style)
			}
			x += g.width
		}
	}
}

func isWhitespace(symbol string) bool {
	if symbol == "​" {
		return true
	}
	if symbol == " " {
		return false
	}
	for _, r := range symbol {
		if !unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

// wordWrap is ratatui's WordWrapper for one line.
func wordWrap(line []grapheme, maxWidth int, trim bool) [][]grapheme {
	var wrapped [][]grapheme
	var pendingLine, pendingWord, pendingWhitespace []grapheme
	lineWidth, wordWidth, whitespaceWidth := 0, 0, 0
	nonWhitespacePrevious := false

	for _, g := range line {
		whitespace := isWhitespace(g.symbol)
		if g.width > maxWidth {
			continue
		}
		wordFound := nonWhitespacePrevious && whitespace
		trimmedOverflow := len(pendingLine) == 0 && trim && wordWidth+g.width > maxWidth
		whitespaceOverflow := len(pendingLine) == 0 && trim && whitespaceWidth+g.width > maxWidth
		untrimmedOverflow := len(pendingLine) == 0 && !trim && wordWidth+whitespaceWidth+g.width > maxWidth
		if wordFound || trimmedOverflow || whitespaceOverflow || untrimmedOverflow {
			if len(pendingLine) > 0 || !trim {
				pendingLine = append(pendingLine, pendingWhitespace...)
				lineWidth += whitespaceWidth
			}
			pendingLine = append(pendingLine, pendingWord...)
			lineWidth += wordWidth
			pendingWord, pendingWhitespace = nil, nil
			whitespaceWidth, wordWidth = 0, 0
		}

		lineFull := lineWidth >= maxWidth
		pendingWordOverflow := g.width > 0 && lineWidth+whitespaceWidth+wordWidth >= maxWidth
		if lineFull || pendingWordOverflow {
			remaining := sat(maxWidth - lineWidth)
			wrapped = append(wrapped, pendingLine)
			pendingLine = nil
			lineWidth = 0
			for len(pendingWhitespace) > 0 {
				width := pendingWhitespace[0].width
				if width > remaining {
					break
				}
				whitespaceWidth -= width
				remaining -= width
				pendingWhitespace = pendingWhitespace[1:]
			}
			if whitespace && len(pendingWhitespace) == 0 {
				continue
			}
		}

		if whitespace {
			whitespaceWidth += g.width
			pendingWhitespace = append(pendingWhitespace, g)
		} else {
			wordWidth += g.width
			pendingWord = append(pendingWord, g)
		}
		nonWhitespacePrevious = !whitespace
	}

	if len(pendingLine) == 0 && len(pendingWord) == 0 && len(pendingWhitespace) > 0 && trim {
		wrapped = append(wrapped, nil)
	}
	if len(pendingLine) > 0 || !trim {
		pendingLine = append(pendingLine, pendingWhitespace...)
	}
	pendingLine = append(pendingLine, pendingWord...)
	if len(pendingLine) > 0 {
		wrapped = append(wrapped, pendingLine)
	}
	if len(wrapped) == 0 {
		wrapped = append(wrapped, nil)
	}
	return wrapped
}

// -- Lists ------------------------------------------------------------------------

// ListItem is one or more lines in a list.
type ListItem struct{ Lines []Line }

func Item(lines ...Line) ListItem { return ListItem{lines} }

// List draws items, keeping the selected one (-1 for none) in view.
type List struct {
	Items     []ListItem
	Block     *Block
	Highlight Style
	Symbol    string
}

func (l List) Render(b *Buffer, area Rect, selected int) {
	if l.Block != nil {
		l.Block.Render(b, area)
		area = l.Block.Inner(area)
	}
	if area.Empty() || len(l.Items) == 0 {
		return
	}
	if selected >= len(l.Items) {
		selected = len(l.Items) - 1
	}
	height := func(i int) int { return len(l.Items[i].Lines) }

	first, last, used := 0, 0, 0
	for i := range l.Items {
		if used+height(i) > area.H {
			break
		}
		used += height(i)
		last++
	}
	show := max(selected, 0)
	for show >= last {
		used += height(last)
		last++
		for used > area.H {
			used -= height(first)
			first++
		}
	}

	symbolWidth := textWidth(l.Symbol)
	spacing := selected >= 0
	y := area.Y
	for i := first; i < last; i++ {
		row := Rect{area.X, y, area.W, height(i)}
		content := row
		if spacing {
			content = Rect{row.X + symbolWidth, row.Y, sat(row.W - symbolWidth), row.H}
		}
		b.RenderText(l.Items[i].Lines, content)
		if i == selected {
			b.SetStyle(row, l.Highlight)
		}
		if spacing {
			for j := 0; j < height(i); j++ {
				symbol := strings.Repeat(" ", symbolWidth)
				if i == selected && j == 0 {
					symbol = l.Symbol
				}
				b.RenderLine(RawLine(symbol), Rect{row.X, row.Y + j, symbolWidth, 1})
			}
		}
		y += height(i)
	}
}
