package tui

// A board: its columns side by side, cards you can open, add and move.

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var boardHints = []hint{{"←→↑↓", "move"}, {"enter", "open"}, {"c", "new"}, {"H L", "move card"}, {"e d", "rename, due"}, {"esc", "home"}}

var boardHelp = []hint{
	{"← → / h l", "Previous or next column"},
	{"↑ ↓ / j k", "Previous or next card"},
	{"enter", "Open the card: description and comments"},
	{"c", "New card at the bottom of this column"},
	{"H L", "Move the card to the previous or next column"},
	{"K J", "Move the card up or down its column"},
	{"e", "Rename the card"},
	{"d", "Set its due date: fri, +3, tomorrow, 2026-10-01 or none"},
	{"i", "Assign the card to yourself, or unassign"},
	{"a", "Archive the card"},
	{"o", "Open the card in your browser"},
	{"u", "Undo the last change"},
	{"r", "Reload the board"},
	{"esc", "Back home"},
}

const columnWidth = 30

type Board struct {
	tool    api.Value
	columns []api.Value
	column  int
	// cards is the selected card in each column.
	cards []int
}

func loadBoard(app *App, tool api.Value) (*Board, error) {
	board, err := app.get(toolPath(tool) + "/board")
	if err != nil {
		return nil, err
	}
	columns := slices.Clone(board.Get("columns").Items())
	return &Board{tool: tool, columns: columns, cards: make([]int, len(columns))}, nil
}

func (s *Board) Tool() (api.Value, bool) { return s.tool, true }
func (s *Board) Hints() []hint           { return boardHints }
func (s *Board) Help() []hint            { return boardHelp }
func (s *Board) toolID() int64           { return s.tool.Get("id").Int() }

func (s *Board) LiveRequest() (string, []api.Param, bool) {
	return toolPath(s.tool) + "/board", nil, true
}

func (s *Board) ApplyLive(value api.Value) {
	s.replace(slices.Clone(value.Get("columns").Items()), 0)
}

func cardsOf(column api.Value) []api.Value { return column.Get("cards").Items() }

func (s *Board) card() (api.Value, bool) {
	if s.column >= len(s.columns) {
		return api.Null, false
	}
	cards := cardsOf(s.columns[s.column])
	if s.cards[s.column] >= len(cards) {
		return api.Null, false
	}
	return cards[s.cards[s.column]], true
}

func (s *Board) Refresh() Job {
	return func(app *App) error { return reloadBoard(app, 0) }
}

// replace takes in fresh columns, keeping the selection on the same card (or on card select, when not 0).
func (s *Board) replace(columns []api.Value, selectID int64) {
	if selectID == 0 {
		if card, ok := s.card(); ok {
			selectID = card.Get("id").Int()
		}
	}
	s.columns = columns
	for len(s.cards) < len(columns) {
		s.cards = append(s.cards, 0)
	}
	s.cards = s.cards[:len(columns)]
	s.column = min(s.column, sat(len(columns)-1))
	if selectID != 0 {
		s.selectCard(selectID)
	}
	for index, column := range s.columns {
		s.cards[index] = min(s.cards[index], sat(len(cardsOf(column))-1))
	}
}

// selectCard selects the card with this id, wherever it is.
func (s *Board) selectCard(id int64) {
	for columnIndex, column := range s.columns {
		if position := slices.IndexFunc(cardsOf(column), func(card api.Value) bool { return card.Get("id").Int() == id }); position >= 0 {
			s.column = columnIndex
			s.cards[columnIndex] = position
		}
	}
}

func (s *Board) Key(key Key, view *View, fx *Fx) bool {
	count := 0
	if s.column < len(s.columns) {
		count = len(cardsOf(s.columns[s.column]))
	}
	switch {
	case key.Code == KeyLeft || key.Is('h'):
		s.column = sat(s.column - 1)
	case key.Code == KeyRight || key.Is('l'):
		s.column = min(s.column+1, sat(len(s.columns)-1))
	case key.Code == KeyDown || key.Is('j'):
		if s.column < len(s.cards) {
			s.cards[s.column] = min(s.cards[s.column]+1, sat(count-1))
		}
	case key.Code == KeyUp || key.Is('k'):
		if s.column < len(s.cards) {
			s.cards[s.column] = sat(s.cards[s.column] - 1)
		}
	case key.Code == KeyEnter:
		if card, ok := s.card(); ok {
			tool, id := s.toolID(), card.Get("id").Int()
			fx.job("Opening the card", func(app *App) error {
				detail, err := cardDetail(app, tool, id)
				if err != nil {
					return err
				}
				app.popup = detail
				return nil
			})
		}
	case key.Is('c'):
		if s.column >= len(s.columns) {
			return true
		}
		column := s.columns[s.column]
		columnID, name := column.Get("id").S(), column.Get("name").S()
		fx.popup = inputPopup("New card in "+name, "What needs doing?", "Adding the card", func(app *App, title string) error {
			card, err := app.post("/columns/"+columnID+"/cards", api.Object("card", api.Object("title", title)))
			if err != nil {
				return err
			}
			if err := reloadBoard(app, card.Get("id").Int()); err != nil {
				return err
			}
			app.say("Added “"+card.Get("title").S()+"” 📝", ToneSuccess)
			return nil
		})
	case key.Is('H', 'L'):
		s.moveAcross(key.Is('L'), fx)
	case key.Is('K', 'J'):
		s.moveWithin(key.Is('J'), fx)
	case key.Is('i'):
		if card, ok := s.card(); ok {
			tool, id, assignee := s.toolID(), card.Get("id").Int(), card.Get("assignee", "id")
			fx.job("Assigning", func(app *App) error {
				mine := assignee.Equal(app.me.Get("id"))
				value := app.me.Get("id")
				if mine {
					value = api.Null
				}
				if err := updateCard(app, tool, id, api.Object("assigned_user_id", value)); err != nil {
					return err
				}
				if mine {
					app.say("Unassigned", ToneSuccess)
				} else {
					app.say("It's yours now 👍", ToneSuccess)
				}
				app.offerUndo("the assignment", func(app *App) error {
					return updateCard(app, tool, id, api.Object("assigned_user_id", assignee))
				})
				return nil
			})
		}
	case key.Is('e'):
		if card, ok := s.card(); ok {
			tool, id, old := s.toolID(), card.Get("id").Int(), card.Get("title").S()
			fx.popup = inputPopup("Rename the card", "A new title", "Renaming", func(app *App, title string) error {
				if err := updateCard(app, tool, id, api.Object("title", title)); err != nil {
					return err
				}
				app.offerUndo("the rename", func(app *App) error { return updateCard(app, tool, id, api.Object("title", old)) })
				return nil
			}).prefilled(card.Get("title").S())
		}
	case key.Is('d'):
		if card, ok := s.card(); ok {
			tool, id, old := s.toolID(), card.Get("id").Int(), card.Get("due_date")
			fx.popup = inputPopup("Due date", "fri, +3, tomorrow, 2026-10-01 or none", "Setting the due date", func(app *App, text string) error {
				due, err := dueDate(text)
				if err != nil {
					return err
				}
				if err := updateCard(app, tool, id, api.Object("due_date", dueValue(due))); err != nil {
					return err
				}
				app.say(dueToast(due), ToneSuccess)
				app.offerUndo("the due date", func(app *App) error { return updateCard(app, tool, id, api.Object("due_date", old)) })
				return nil
			}).prefilled(card.Get("due_date").S())
		}
	case key.Is('a'):
		if card, ok := s.card(); ok {
			tool, id, title := s.toolID(), card.Get("id").Int(), card.Get("title").S()
			path := fmt.Sprintf("/tools/%d/board/cards/%d/archive", tool, id)
			fx.popup = confirmPopup("Archive “"+title+"”? You can bring it back in the browser.", "Archiving", func(app *App) error {
				if _, err := app.post(path, api.Object()); err != nil {
					return err
				}
				if err := reloadBoard(app, 0); err != nil {
					return err
				}
				app.say("Archived 📦", ToneSuccess)
				app.offerUndo("the archiving", func(app *App) error {
					if _, err := app.delete(path); err != nil {
						return err
					}
					return reloadBoard(app, id)
				})
				return nil
			})
		}
	case key.Is('o'):
		card, ok := s.card()
		if !ok {
			return false
		}
		fx.openURL = ptr(fmt.Sprintf("/tools/%d/board?card=%s", s.toolID(), card.Get("id").S()))
	default:
		return false
	}
	return true
}

// dueValue is a due date for the server: the date, or null to clear it.
func dueValue(due *time.Time) any {
	if due == nil {
		return nil
	}
	return due.Format(command.DateLayout)
}

// dueToast says what the due date became.
func dueToast(due *time.Time) string {
	if due == nil {
		return "No due date"
	}
	return "Due " + shortDate(due.Format(command.DateLayout))
}

// moveAcross moves the selected card to the bottom of the next or previous column, right away on screen.
func (s *Board) moveAcross(forward bool, fx *Fx) {
	target := s.column - 1
	if forward {
		target = s.column + 1
	}
	if target < 0 || target >= len(s.columns) {
		return
	}
	if _, ok := s.card(); !ok {
		return
	}
	fromColumn, fromPosition := s.columns[s.column].Get("id"), s.cards[s.column]
	card := s.takeCard(s.column, s.cards[s.column])
	tool, id := s.toolID(), card.Get("id").Int()
	columnID, columnName := s.columns[target].Get("id"), s.columns[target].Get("name").S()
	cards := append(slices.Clone(cardsOf(s.columns[target])), card)
	s.columns[target] = s.columns[target].With("cards", cards)
	s.column = target
	s.cards[target] = len(cards) - 1
	if isDoneColumn(columnName) {
		fx.confetti = true
	}
	path := fmt.Sprintf("/tools/%d/board/cards/%d/position", tool, id)
	fx.job("Moving to "+columnName, func(app *App) error {
		if _, err := app.patch(path, api.Object("column_id", columnID)); err != nil {
			return err
		}
		if err := reloadBoard(app, id); err != nil {
			return err
		}
		app.offerUndo("the move", func(app *App) error {
			if _, err := app.patch(path, api.Object("column_id", fromColumn, "position", fromPosition)); err != nil {
				return err
			}
			return reloadBoard(app, id)
		})
		return nil
	})
}

// moveWithin moves the selected card up or down its column, right away on screen.
func (s *Board) moveWithin(down bool, fx *Fx) {
	if _, ok := s.card(); !ok {
		return
	}
	column, index := s.column, s.cards[s.column]
	cards := slices.Clone(cardsOf(s.columns[column]))
	target := index - 1
	if down {
		target = index + 1
	}
	if target < 0 || target >= len(cards) {
		return
	}
	cards[index], cards[target] = cards[target], cards[index]
	s.columns[column] = s.columns[column].With("cards", cards)
	s.cards[column] = target
	tool, id := s.toolID(), cards[target].Get("id").Int()
	path := fmt.Sprintf("/tools/%d/board/cards/%d/position", tool, id)
	fx.job("Moving", func(app *App) error {
		if _, err := app.patch(path, api.Object("position", target)); err != nil {
			return err
		}
		if err := reloadBoard(app, id); err != nil {
			return err
		}
		app.offerUndo("the move", func(app *App) error {
			if _, err := app.patch(path, api.Object("position", index)); err != nil {
				return err
			}
			return reloadBoard(app, id)
		})
		return nil
	})
}

func (s *Board) takeCard(column, index int) api.Value {
	cards := slices.Clone(cardsOf(s.columns[column]))
	card := cards[index]
	cards = slices.Delete(cards, index, index+1)
	s.columns[column] = s.columns[column].With("cards", cards)
	s.cards[column] = min(s.cards[column], sat(len(cards)-1))
	return card
}

func (s *Board) Draw(b *Buffer, area Rect, view *View) {
	if len(s.columns) == 0 {
		Paragraph{Lines: []Line{RawLine("This board has no columns yet.")}, Style: dim(), Block: panel("Board", true)}.Render(b, area)
		return
	}
	fits := max(area.W/columnWidth, 1)
	first := min(sat(s.column-(fits-1)), sat(len(s.columns)-fits))
	shown := min(fits, len(s.columns)-first)
	areas := splitEqual(area, shown)
	for slot := range shown {
		s.drawColumn(b, areas[slot], first+slot)
	}
	if first > 0 {
		b.RenderSpan(Styled("◀", Style{}.Fg(accent())), Rect{area.X, area.Y, 1, 1})
	}
	if first+shown < len(s.columns) {
		b.RenderSpan(Styled("▶", Style{}.Fg(accent())), Rect{area.Right() - 1, area.Y, 1, 1})
	}
}

func (s *Board) drawColumn(b *Buffer, area Rect, index int) {
	column := s.columns[index]
	cards := cardsOf(column)
	focused := index == s.column
	block := panel(fmt.Sprintf("%s %d", column.Get("name").S(), len(cards)), focused)
	inner := block.Inner(area)
	block.Render(b, area)

	if len(cards) == 0 {
		hint := "Nothing here."
		if focused {
			hint = "Nothing here. Press c to add a card."
		}
		Paragraph{Lines: []Line{RawLine(hint)}, Style: dim(), Wrap: true, Trim: true}.Render(b, inner)
		return
	}

	width := sat(inner.W - 2)
	heights := make([]int, len(cards))
	for i, card := range cards {
		heights[i] = len(cardLines(card, width)) + 2
	}
	selectedCard := s.cards[index]
	// Scroll so the selected card is fully in view.
	first := 0
	for first < selectedCard {
		sum := 0
		for _, height := range heights[first : selectedCard+1] {
			sum += height
		}
		if sum <= inner.H {
			break
		}
		first++
	}

	y := inner.Y
	for position := first; position < len(cards); position++ {
		card := cards[position]
		height := heights[position]
		if y >= inner.Bottom() {
			break
		}
		room := inner.Bottom() - y
		cardArea := Rect{inner.X, y, inner.W, min(height, room)}
		chosen := focused && position == selectedCard
		color, ok := cardColor(card.Get("color").S())
		if !ok {
			color = muted()
		}
		cardBlock := &Block{Border: Rounded, BorderStyle: Style{}.Fg(color)}
		style := Style{}
		if chosen {
			cardBlock = &Block{Border: Thick, BorderStyle: Style{}.Fg(accent())}
			style = bold()
		}
		Paragraph{Lines: cardLines(card, width), Style: style, Block: cardBlock}.Render(b, cardArea)
		y += height
	}
	if first > 0 {
		b.RenderSpan(Styled(fmt.Sprintf("↑ %d more", first), dim()), Rect{area.X + 2, area.Y, 12, 1})
	}
}

// reloadBoard reloads the board on screen, selecting card when it's not 0.
func reloadBoard(app *App, card int64) error {
	board, ok := app.screen.(*Board)
	if !ok {
		return nil
	}
	fresh, err := app.get(toolPath(board.tool) + "/board")
	if err != nil {
		return err
	}
	if board, ok := app.screen.(*Board); ok {
		board.replace(slices.Clone(fresh.Get("columns").Items()), card)
	}
	return nil
}

func updateCard(app *App, tool, id int64, attributes api.Value) error {
	if _, err := app.patch(fmt.Sprintf("/tools/%d/board/cards/%d", tool, id), api.Object("card", attributes)); err != nil {
		return err
	}
	return reloadBoard(app, id)
}

// cardLines are the lines inside a card: its title, then due date, assignee and counts.
func cardLines(card api.Value, width int) []Line {
	var lines []Line
	for i, line := range wrap(card.Get("title").S(), width) {
		if i == 3 {
			break
		}
		lines = append(lines, RawLine(line))
	}

	var meta []Span
	if due := card.Get("due_date"); !due.IsNull() {
		style := dim()
		if due.S() < command.Today().Format(command.DateLayout) {
			style = Style{}.Fg(danger())
		}
		meta = append(meta, Styled("📅 "+shortDate(due.S())+" ", style))
	}
	if name := card.Get("assignee", "name"); !name.IsNull() {
		first := ""
		if fields := strings.Fields(name.S()); len(fields) > 0 {
			first = fields[0]
		}
		meta = append(meta, Styled("@"+first+" ", Style{}.Fg(personColor(name.S()))))
	}
	if count := card.Get("comments_count").Int(); count > 0 {
		meta = append(meta, Styled(fmt.Sprintf("💬%d ", count), dim()))
	}
	if count := card.Get("attachments_count").Int(); count > 0 {
		meta = append(meta, Styled(fmt.Sprintf("📎%d ", count), dim()))
	}
	if len(meta) > 0 {
		lines = append(lines, LineOf(meta...))
	}
	for i, line := range lines {
		lines[i] = truncateLine(line, width)
	}
	return lines
}

func truncateLine(line Line, width int) Line {
	if line.Width() <= width {
		return line
	}
	style := Style{}
	if len(line.Spans) > 0 {
		style = line.Spans[0].Style
	}
	return LineOf(Styled(truncate(line.Text(), width), style))
}

// shortDate is "Oct 1" from "2026-10-01".
func shortDate(date string) string {
	if parsed, ok := command.ParseDate(date); ok {
		return parsed.Format("Jan 2")
	}
	return date
}

// cardDetail is the popup for a card: its details, description, comments and files.
func cardDetail(app *App, tool, id int64) (*Detail, error) {
	card, err := app.get(fmt.Sprintf("/tools/%d/board/cards/%d", tool, id))
	if err != nil {
		return nil, err
	}
	var lines []Line
	field(&lines, "Column", card.Get("column", "name").S())
	field(&lines, "Assignee", card.Get("assignee", "name").S())
	if due := card.Get("due_date"); !due.IsNull() {
		field(&lines, "Due", shortDate(due.S()))
	}
	field(&lines, "Color", card.Get("color").S())
	field(&lines, "Created", ago(card.Get("created_at"))+" by "+card.Get("creator", "name").S())

	if description := card.Get("description").S(); strings.TrimSpace(description) != "" {
		heading(&lines, "Description")
		addText(&lines, description, 0)
	}
	comments(&lines, card)
	attachmentLines(&lines, card)

	var url *string
	if value := card.Get("url"); !value.IsNull() {
		url = ptr(value.S())
	}
	return &Detail{
		title: card.Get("title").S(),
		lines: lines,
		url:   url,
		comment: &CommentOn{
			path:   fmt.Sprintf("/tools/%d/board/cards/%d/comments", tool, id),
			reload: func(app *App) (*Detail, error) { return cardDetail(app, tool, id) },
		},
	}, nil
}

func attachmentLines(lines *[]Line, record api.Value) {
	attachments := record.Get("attachments").Items()
	if len(attachments) == 0 {
		return
	}
	heading(lines, fmt.Sprintf("📎 Attachments (%d)", len(attachments)))
	for _, attachment := range attachments {
		*lines = append(*lines, RawLine(fmt.Sprintf("  %s  %s", attachment.Get("filename").S(), command.Bytes(attachment.Get("file_size")))))
	}
}
