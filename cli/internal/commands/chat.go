package commands

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

// reactions are the emoji the app offers; anything else is refused.
var reactions = []string{"👍", "❤️", "😂", "🎉", "😮", "🙏", "👀", "✅"}

func chat() []*Definition {
	return []*Definition{
		New("chat list", "Show the latest messages in a chat, oldest first (doesn't mark it read)", []string{"TOOL"},
			[]Flag{
				F("limit", "N", "Number of messages (default 50, max 200)"),
				F("before", "ID", "Only messages older than this message, to page back"),
			}, listChat),
		New("chat post", "Send a message to a chat", []string{"TOOL", "TEXT"},
			[]Flag{Switch("html", "TEXT is HTML"), F("reply-to", "ID", "Reply to this message")}, postChat),
		New("chat edit", "Change the text of one of your messages", []string{"TOOL/MESSAGE", "TEXT"},
			[]Flag{Switch("html", "TEXT is HTML")}, editChat),
		New("chat delete", "Delete a message (your own, or anyone's if you own the chat)", []string{"TOOL/MESSAGE"}, nil, deleteChat),
		New("chat react", fmt.Sprintf("Put an emoji on a message, or take yours off (%s)", strings.Join(reactions, " ")),
			[]string{"TOOL/MESSAGE", "EMOJI"}, []Flag{Switch("remove", "Take your emoji off instead")}, reactChat),
		New("chat read", "Mark a chat as read up to its latest message", []string{"TOOL"}, nil, readChat),
	}
}

func listChat(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "chat")
	if err != nil {
		return err
	}
	limit, hasLimit := args.Flag("limit")
	before := ""
	if value, ok := args.Flag("before"); ok {
		if before, err = messageID(value); err != nil {
			return err
		}
	}
	chat, err := ctx.Get(fmt.Sprintf("/tools/%s/chat", tool.Get("id").S()), "limit", limit, "before", before)
	if err != nil {
		return err
	}

	return ctx.Output(chat, func() error {
		messages := chat.Get("messages").Items()
		ctx.Sayf("%s (chat %s) %s", tool.Get("name").S(), tool.Get("id").S(), chat.Get("url").S())
		if len(messages) == 0 {
			ctx.Say("  (no messages)")
		}
		if chat.Get("has_more").Truthy() {
			oldest := ""
			if len(messages) > 0 {
				oldest = messages[0].Get("id").S()
			}
			ctx.Sayf("  Older messages: dobase chat list %s --before %s%s", tool.Get("id").S(), oldest, If(hasLimit, " --limit "+limit))
		}

		for _, message := range messages {
			ctx.Blank()
			ctx.Sayf("%s · %s%s [message %s/%s]", message.Get("user", "name").Or("Former member"), Moment(message.Get("created_at")),
				If(message.Get("edited_at").Truthy(), " (edited)"), tool.Get("id").S(), message.Get("id").S())
			if message.Get("reply_to").Truthy() {
				ctx.Sayf("  > %s: %s", message.Get("reply_to", "user_name").S(), message.Get("reply_to", "preview").S())
			}
			ctx.Paragraph(message.Get("body").S(), 2)
			for _, file := range message.Get("files").Items() {
				ctx.Sayf("  File: %s (%s) %s", file.Get("filename").S(), Bytes(file.Get("byte_size")), file.Get("download_url").S())
			}
			var list []string
			for _, reaction := range message.Get("reactions").Items() {
				var names []string
				for _, user := range reaction.Get("users").Items() {
					names = append(names, user.Get("name").S())
				}
				list = append(list, reaction.Get("emoji").S()+" "+strings.Join(names, ", "))
			}
			if len(list) > 0 {
				ctx.Say("  Reactions: " + strings.Join(list, " · "))
			}
		}
		return nil
	})
}

func postChat(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "chat")
	if err != nil {
		return err
	}
	var replyTo any
	if value, ok := args.Flag("reply-to"); ok {
		if replyTo, err = messageID(value); err != nil {
			return err
		}
	}
	body, err := ctx.RichText(args.At(1), args.On("html"))
	if err != nil {
		return err
	}

	message, err := ctx.Post(fmt.Sprintf("/tools/%s/chat/messages", tool.Get("id").S()),
		map[string]any{"message": Compact(map[string]any{"body": body, "reply_to_id": replyTo})})
	if err != nil {
		return err
	}
	return ctx.Output(message, func() error {
		ctx.Sayf("Posted message %s/%s to %s.", tool.Get("id").S(), message.Get("id").S(), tool.Get("name").S())
		return nil
	})
}

func editChat(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "chat", "message")
	if err != nil {
		return err
	}
	body, err := ctx.RichText(args.At(1), args.On("html"))
	if err != nil {
		return err
	}
	message, err := ctx.Patch(fmt.Sprintf("/tools/%s/chat/messages/%d", tool.Get("id").S(), id), map[string]any{"message": map[string]any{"body": body}})
	if err != nil {
		return err
	}
	return ctx.Output(message, func() error {
		ctx.Sayf("Edited message %s/%s.", tool.Get("id").S(), message.Get("id").S())
		return nil
	})
}

func deleteChat(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "chat", "message")
	if err != nil {
		return err
	}
	if _, err := ctx.Delete(fmt.Sprintf("/tools/%s/chat/messages/%d", tool.Get("id").S(), id)); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted message %s/%d.", tool.Get("id").S(), id)
		return nil
	})
}

func reactChat(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "chat", "message")
	if err != nil {
		return err
	}
	emoji, remove := args.At(1), args.On("remove")
	path := fmt.Sprintf("/tools/%s/chat/messages/%d/reactions", tool.Get("id").S(), id)

	var message api.Value
	if remove {
		message, err = ctx.Delete(path + "/" + url.QueryEscape(emoji))
	} else {
		message, err = ctx.Post(path, map[string]any{"emoji": emoji})
	}
	if err != nil {
		return err
	}
	return ctx.Output(message, func() error {
		action := "Put " + emoji + " on"
		if remove {
			action = "Took " + emoji + " off"
		}
		ctx.Sayf("%s message %s/%d.", action, tool.Get("id").S(), id)
		return nil
	})
}

func readChat(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "chat")
	if err != nil {
		return err
	}
	receipt, err := ctx.Post(fmt.Sprintf("/tools/%s/chat/read", tool.Get("id").S()), map[string]any{})
	if err != nil {
		return err
	}
	return ctx.Output(receipt, func() error {
		ctx.Sayf("Marked %s as read.", tool.Get("name").S())
		return nil
	})
}

// messageID is a message id, or a TOOL/MESSAGE reference as printed by `chat list`.
func messageID(value string) (string, error) {
	id := value[strings.LastIndex(value, "/")+1:]
	if !IsDigits(id) {
		return "", api.Usagef("Expected a message id like 104, got %s.", Quoted(value))
	}
	return id, nil
}

func isBlank(text string) bool { return strings.TrimSpace(text) == "" }
