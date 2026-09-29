package tui

// Home: the logo, a hello, your tools and what's new.

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

var homeHelp = []hint{
	{"↑↓ / j k", "Choose a tool"},
	{"enter", "Open it"},
	{"1-9", "Open the first nine tools"},
	{"tab", "Switch between tools and notifications"},
	{"x", "Mark the chosen notification read"},
	{"] [", "Next or previous tool, from anywhere"},
	{"/", "Search everything"},
	{"n", "Notifications"},
	{"o", "Open Dobase in your browser"},
	{"r", "Reload"},
	{"esc / g", "Back home, from anywhere"},
	{"q", "Quit"},
}

// homeNotifications is how many notifications home shows.
const homeNotifications = 12

type Home struct {
	selected        int
	notifications   []api.Value
	notification    int
	onNotifications bool
}

func loadHome(app *App) (*Home, error) {
	notifications, err := app.get("/notifications", api.Param{Name: "limit", Value: strconv.Itoa(homeNotifications)})
	if err != nil {
		return nil, err
	}
	return &Home{notifications: slices.Clone(notifications.Items())}, nil
}

func (h *Home) Tool() (api.Value, bool) { return api.Null, false }
func (h *Home) Refresh() Job            { return nil }
func (h *Home) Help() []hint            { return homeHelp }

func (h *Home) Hints() []hint {
	return []hint{{"↑↓", "choose"}, {"enter", "open"}, {"/", "search"}, {"n", "notifications"}, {"q", "quit"}}
}

func (h *Home) LiveRequest() (string, []api.Param, bool) {
	return "/notifications", []api.Param{{Name: "limit", Value: strconv.Itoa(homeNotifications)}}, true
}

func (h *Home) ApplyLive(value api.Value) { h.replaceNotifications(slices.Clone(value.Items())) }

func (h *Home) replaceNotifications(notifications []api.Value) {
	selectedID, had := int64(0), h.notification < len(h.notifications)
	if had {
		selectedID = h.notifications[h.notification].Get("id").Int()
	}
	h.notifications = notifications
	h.notification = 0
	if had {
		if index := slices.IndexFunc(notifications, func(n api.Value) bool { return n.Get("id").Int() == selectedID }); index >= 0 {
			h.notification = index
		}
	}
}

func (h *Home) Key(key Key, view *View, fx *Fx) bool {
	switch {
	case key.OneOf(KeyTab, KeyBackTab):
		h.onNotifications = !h.onNotifications && len(h.notifications) > 0
	case key.Code == KeyRune && key.Rune >= '1' && key.Rune <= '9':
		if index := int(key.Rune - '1'); index < len(view.tools) {
			fx.openTool = ptr(view.tools[index].Get("id").Int())
		}
	case (key.Code == KeyEnter || key.Is('l') || key.Code == KeyRight) && !h.onNotifications:
		if h.selected < len(view.tools) {
			fx.openTool = ptr(view.tools[h.selected].Get("id").Int())
		}
	case key.Code == KeyEnter && h.onNotifications:
		if h.notification < len(h.notifications) {
			openNotification(&h.notifications[h.notification], fx)
		}
	case key.Is('x') && h.onNotifications:
		if h.notification < len(h.notifications) {
			id := h.notifications[h.notification].Get("id").S()
			h.notifications[h.notification] = h.notifications[h.notification].With("read", true)
			fx.job("Marking it read", func(app *App) error {
				_, err := app.post("/notifications/"+id+"/read", api.Object())
				return err
			})
		}
	case h.onNotifications:
		return moveSelection(&h.notification, len(h.notifications), key)
	default:
		return moveSelection(&h.selected, len(view.tools), key)
	}
	return true
}

func (h *Home) Draw(b *Buffer, area Rect, view *View) {
	compact := area.H < 18
	logoHeight := 6
	if compact {
		logoHeight = 0
	}
	parts := splitVertical(area, Length(logoHeight), Length(3), Min(5), Length(1))
	logoArea, helloArea, listsArea, tipArea := parts[0], parts[1], parts[2], parts[3]

	if !compact {
		Paragraph{Lines: logo(view.tick), Align: AlignCenter}.Render(b, logoArea)
	}

	firstName := "there"
	if fields := strings.Fields(view.me.Get("name").S()); len(fields) > 0 {
		firstName = fields[0]
	}
	unread := 0
	for _, notification := range h.notifications {
		if !notification.Get("read").Truthy() {
			unread++
		}
	}
	var summary string
	switch unread {
	case 0:
		summary = fmt.Sprintf("%d tools · nothing new, enjoy the quiet", len(view.tools))
	case 1:
		summary = fmt.Sprintf("%d tools · 1 new notification", len(view.tools))
	default:
		summary = fmt.Sprintf("%d tools · %d new notifications", len(view.tools), unread)
	}
	Paragraph{Lines: []Line{
		StyledLine(greeting(time.Now().Hour(), firstName), bold()),
		StyledLine(summary, dim()),
	}, Align: AlignCenter}.Render(b, helloArea)

	toolsArea, notificationsArea := splitPercentages(listsArea, 45)
	h.drawTools(b, toolsArea, view)
	h.drawNotifications(b, notificationsArea)

	tip := tips[(view.tick/100)%uint64(len(tips))]
	b.RenderLine(StyledLine("💡 "+tip, dim()).Centered(), tipArea)
}

func (h *Home) drawTools(b *Buffer, area Rect, view *View) {
	if len(view.tools) == 0 {
		Paragraph{
			Lines: []Line{RawLine("No tools yet. Make one in the browser, or: dobase tool create")},
			Style: dim(),
			Block: panel("Your tools", true),
		}.Render(b, area)
		return
	}
	width := sat(area.W - 4)
	items := make([]ListItem, len(view.tools))
	for index, tool := range view.tools {
		number := "  "
		if index < 9 {
			number = fmt.Sprintf("%d ", index+1)
		}
		kind := tool.Get("type").S()
		spans := []Span{
			Styled(number, dim()),
			Raw(toolIcon(kind) + " "),
			Styled(truncate(tool.Get("name").S(), sat(width-18)), bold()),
			Styled("  "+kind, dim()),
		}
		if tool.Get("unread").Truthy() {
			spans = append(spans, Styled(" ●", Style{}.Fg(accent())))
		}
		items[index] = Item(LineOf(spans...))
	}
	highlight := selected()
	if h.onNotifications {
		highlight = bold()
	}
	h.selected = min(h.selected, len(view.tools)-1)
	List{Items: items, Block: panel("Your tools", !h.onNotifications), Highlight: highlight, Symbol: "▸ "}.Render(b, area, h.selected)
}

func (h *Home) drawNotifications(b *Buffer, area Rect) {
	block := panel("What's new", h.onNotifications)
	if len(h.notifications) == 0 {
		Paragraph{Lines: []Line{RawLine(""), {Spans: []Span{Raw("  All caught up ✨")}, Style: dim()}}, Block: block}.Render(b, area)
		return
	}
	width := sat(area.W - 6)
	items := make([]ListItem, len(h.notifications))
	for i, notification := range h.notifications {
		items[i] = notificationItem(notification, width)
	}
	highlight := Style{}
	if h.onNotifications {
		highlight = selected()
	}
	h.notification = min(h.notification, len(h.notifications)-1)
	chosen := -1
	if h.onNotifications {
		chosen = h.notification
	}
	List{Items: items, Block: block, Highlight: highlight}.Render(b, area, chosen)
}

// toolIDIn is the tool id in a Dobase URL such as /tools/12/board?card=3.
func toolIDIn(url string) (int64, bool) {
	_, rest, found := strings.Cut(url, "/tools/")
	if !found {
		return 0, false
	}
	end := strings.IndexFunc(rest, func(r rune) bool { return r < '0' || r > '9' })
	if end >= 0 {
		rest = rest[:end]
	}
	id, err := strconv.ParseInt(rest, 10, 64)
	return id, err == nil
}

// openNotification opens what a notification is about, and marks it read like the web app does.
func openNotification(notification *api.Value, fx *Fx) {
	if !notification.Get("read").Truthy() {
		*notification = notification.With("read", true)
		id := notification.Get("id").S()
		fx.job("Marking it read", func(app *App) error {
			_, err := app.post("/notifications/"+id+"/read", api.Object())
			return err
		})
	}
	if url := notification.Get("url"); !url.IsNull() {
		fx.openLink = ptr(url.S())
	} else {
		fx.say("That notification doesn't lead anywhere.", ToneInfo)
	}
}
