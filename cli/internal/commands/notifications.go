package commands

import (
	"strconv"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func notifications() []*Definition {
	return []*Definition{
		New("notification list", "List your notifications, newest first (* = unread)", nil,
			[]Flag{Switch("unread", "Only unread notifications"), F("limit", "N", "Number of notifications (default 20, max 100)")},
			listNotifications),
		New("notification read", "Mark a notification as read, or all of them with --all", []string{"[ID]"},
			[]Flag{Switch("all", "Mark every notification as read")}, readNotification),
	}
}

func listNotifications(ctx *Ctx, args *Args) error {
	unread := args.On("unread")
	notifications, err := ctx.Call("notification_list", toolArgs("unread", unread, "limit", limitArg(args.Value("limit"), 100)))
	if err != nil {
		return err
	}

	return ctx.Output(notifications, func() error {
		items := notifications.Items()
		if len(items) == 0 {
			if unread {
				ctx.Say("No unread notifications.")
			} else {
				ctx.Say("No notifications.")
			}
		}
		var rows [][]string
		for _, notification := range items {
			rows = append(rows, []string{
				If(!notification.Get("read").Truthy(), "*"),
				notification.Get("id").S(),
				Moment(notification.Get("created_at")),
				notification.Get("message").S(),
				notification.Get("url").S(),
			})
		}
		ctx.Table(rows, 0)
		return nil
	})
}

// limitArg is a --limit as a tool takes it: within 1 and max, as the server
// would have made it, and left out when it isn't a number (the server's default).
func limitArg(text string, most int64) any {
	n, err := strconv.ParseInt(strings.TrimSpace(text), 10, 64)
	if err != nil {
		return nil
	}
	return min(max(n, 1), most)
}

func readNotification(ctx *Ctx, args *Args) error {
	id, all := args.Get(0), args.On("all")
	if id != "" && all {
		return api.Usagef("Give a notification ID or --all, not both.")
	}

	switch {
	case id == "" && !all:
		return api.Usagef("Give a notification ID or --all. `dobase notification list` shows the ids.")
	case id == "":
		result, err := ctx.Call("notification_read", nil)
		if err != nil {
			return err
		}
		return ctx.Output(result, func() error {
			ctx.Sayf("Marked %s as read.", Count(result.Get("marked_as_read").Int(), "notification"))
			return nil
		})
	}

	if !IsDigits(id) {
		return api.Usagef("Expected a notification id like 41, got %s.", Quoted(id))
	}
	number, _ := strconv.ParseInt(id, 10, 64)
	notification, err := ctx.Call("notification_read", toolArgs("notification_id", number))
	if err != nil {
		return err
	}
	return ctx.Output(notification, func() error {
		ctx.Sayf("Marked notification %s as read: %s", notification.Get("id").S(), notification.Get("message").S())
		return nil
	})
}
