package commands

import (
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

// mailViews are the views `mail list` shows, with their names.
var mailViews = [][2]string{
	{"inbox", "Inbox"}, {"drafts", "Drafts"}, {"starred", "Starred"}, {"sent", "Sent"}, {"archive", "Archive"}, {"trash", "Trash"},
}

const (
	mailTo   = "Recipients, comma-separated"
	mailCc   = "Cc recipients, comma-separated"
	mailBcc  = "Bcc recipients, comma-separated"
	mailBody = "Message (plain text, or HTML with --html)"
	mailOpen = "Open the saved draft in the Dobase app or your browser, ready to edit and send"
)

func mail() []*Definition {
	views := make([]string, len(mailViews))
	for i, view := range mailViews {
		views[i] = view[0]
	}
	return []*Definition{
		New("mail list", "List the conversations in a folder (inbox unless --folder)", []string{"TOOL"},
			[]Flag{
				F("folder", "FOLDER", strings.Join(views, ", ")+" or a custom folder"),
				F("search", "QUERY", "Only conversations whose subject, sender or text matches"),
				F("page", "N", "Page (30 conversations per page)"),
			}, listMail),
		New("mail show", "Show a conversation: every message in it, oldest first", []string{"TOOL/MESSAGE"},
			[]Flag{Switch("html", "Print the HTML of each message instead of its text")}, showMail),
		New("mail read", "Mark a message as read, here and on the mail server", []string{"TOOL/MESSAGE"}, nil, readMail),
		New("mail unread", "Mark a message as unread, here and on the mail server", []string{"TOOL/MESSAGE"}, nil, unreadMail),
		New("mail star", "Star a message (flagged on the mail server)", []string{"TOOL/MESSAGE"}, nil, starMail),
		New("mail unstar", "Remove the star from a message", []string{"TOOL/MESSAGE"}, nil, unstarMail),
		New("mail archive", "Archive a message (moved to the account's archive folder on the server, if it has one)",
			[]string{"TOOL/MESSAGE"}, nil, archiveMail),
		New("mail unarchive", "Move an archived message back to the inbox", []string{"TOOL/MESSAGE"}, nil, unarchiveMail),
		New("mail move", "Move a message to another folder on the mail server: INBOX, Sent or a custom folder",
			[]string{"TOOL/MESSAGE", "FOLDER"}, nil, moveMail),
		New("mail draft", "Save a new draft (nothing is sent; it is copied to the server's Drafts folder)", []string{"TOOL"},
			[]Flag{
				F("to", "ADDRS", mailTo),
				F("cc", "ADDRS", mailCc),
				F("bcc", "ADDRS", mailBcc),
				F("subject", "TEXT", "Subject"),
				F("body", "TEXT", mailBody),
				Switch("html", "The body is HTML"),
				Switch("open", mailOpen),
			}, draftMail),
		New("mail update", "Change a saved draft: only what you pass changes, and nothing is sent", []string{"TOOL/DRAFT"},
			[]Flag{
				F("to", "ADDRS", mailTo),
				F("cc", "ADDRS", mailCc),
				F("bcc", "ADDRS", mailBcc),
				F("subject", "TEXT", "Subject"),
				F("body", "TEXT", mailBody),
				Switch("html", "The body is HTML"),
				Switch("open", mailOpen),
			}, updateMailDraft),
		New("mail reply", "Reply to a message, quoting it below your text: saves a draft, or sends real email right away with --send", []string{"TOOL/MESSAGE"},
			[]Flag{
				F("body", "TEXT", "Your reply (plain text, or HTML with --html)"),
				Switch("all", "Reply to all: cc everyone else on the message"),
				Switch("html", "The body is HTML"),
				Switch("send", "Send it now through the mail server instead of saving a draft"),
				Switch("open", mailOpen),
			}, replyMail),
		New("mail forward", "Forward a message with its attachments: saves a draft, or sends real email right away with --send",
			[]string{"TOOL/MESSAGE"},
			[]Flag{
				F("to", "ADDRS", mailTo),
				F("cc", "ADDRS", mailCc),
				F("body", "TEXT", "A note above the forwarded message (plain text, or HTML with --html)"),
				Switch("html", "The body is HTML"),
				Switch("send", "Send it now through the mail server instead of saving a draft"),
				Switch("open", mailOpen),
			}, forwardMail),
		New("mail attachments", "List a message's attachments, or download them with --save or --name", []string{"TOOL/MESSAGE"},
			[]Flag{
				F("save", "DIR", "Download every attachment into DIR"),
				F("name", "FILENAME", "Only this attachment (into the current directory unless --save)"),
				Switch("force", "Overwrite existing files"),
			}, mailAttachments),
		New("mail send", "Send real email now through the mail server; --draft ID sends a saved draft as it is", []string{"TOOL"},
			[]Flag{
				F("to", "ADDRS", mailTo),
				F("cc", "ADDRS", mailCc),
				F("bcc", "ADDRS", mailBcc),
				F("subject", "TEXT", "Subject"),
				F("body", "TEXT", mailBody),
				Switch("html", "The body is HTML"),
				F("draft", "ID", "Send this saved draft instead (it leaves Drafts)"),
			}, sendMail),
		New("mail sync", "Fetch new mail from the mail server now (runs in the background)", []string{"TOOL"}, nil, syncMail),
		New("mail contacts", "Find addresses you've mailed or received mail from", []string{"TOOL", "QUERY"}, nil, mailContacts),
	}
}

func listMail(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "mail")
	if err != nil {
		return err
	}
	folder, hasFolder := args.Flag("folder")
	search, hasSearch := args.Flag("search")
	page, hasPage := args.Flag("page")

	// Given flags are sent even when empty, so this doesn't go through ctx.Get.
	var params []api.Param
	for _, param := range []struct {
		name, value string
		given       bool
	}{{"folder", folder, hasFolder}, {"q", search, hasSearch}, {"page", page, hasPage}} {
		if param.given {
			params = append(params, api.Param{Name: param.name, Value: param.value})
		}
	}
	server, err := ctx.API()
	if err != nil {
		return err
	}
	mailbox, err := server.Request(api.Get, fmt.Sprintf("/tools/%s/mails", tool.Get("id").S()), params, nil)
	if err != nil {
		return err
	}

	return ctx.Output(mailbox, func() error {
		ctx.Sayf("%s (mail %s) %s", tool.Get("name").S(), tool.Get("id").S(), mailbox.Get("account", "email_address").S())
		view := mailbox.Get("folder").S()
		for _, known := range mailViews {
			if known[0] == view {
				view = known[1]
				break
			}
		}
		matching := If(hasSearch, " matching "+Quoted(search))
		ctx.Sayf("%s%s: %s, page %s of %d", view, matching, Count(mailbox.Get("total_count").Int(), "conversation"),
			mailbox.Get("page").S(), max(mailbox.Get("total_pages").Int(), 1))
		ctx.Blank()

		conversations := mailbox.Get("conversations").Items()
		if len(conversations) == 0 {
			ctx.Say("  (no conversations)")
		}
		var rows [][]string
		for _, conversation := range conversations {
			from := conversation.Get("from").S()
			if conversation.Get("draft").Truthy() {
				from = "Draft"
			}
			rows = append(rows, []string{
				tool.Get("id").S() + "/" + conversation.Get("id").S(),
				Moment(conversation.Get("sent_at")),
				from,
				conversation.Get("subject").S(),
				mailConversationSummary(conversation),
			})
		}
		ctx.Table(rows, 2)

		if mailbox.Get("page").Int() < mailbox.Get("total_pages").Int() {
			ctx.Blank()
			next := strconv.FormatInt(mailbox.Get("page").Int()+1, 10)
			var options []string
			if hasFolder {
				options = append(options, "--folder "+shellEscape(folder))
			}
			if hasSearch {
				options = append(options, "--search "+shellEscape(search))
			}
			options = append(options, "--page "+shellEscape(next))
			ctx.Sayf("More: dobase mail list %s %s", tool.Get("id").S(), strings.Join(options, " "))
		}
		ctx.Blank()
		ctx.Sayf("Folders: %s", mailFolderSummary(mailbox))
		return nil
	})
}

func showMail(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	html := args.On("html")
	conversation, err := ctx.Get(fmt.Sprintf("/tools/%s/mails/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}

	return ctx.Output(conversation, func() error {
		messages := conversation.Get("messages").Items()
		ctx.Sayf("%s (%s)", conversation.Get("subject").S(), Count(int64(len(messages)), "message"))

		for _, message := range messages {
			ctx.Blank()
			ctx.Sayf("[%s/%s] %s · %s", tool.Get("id").S(), message.Get("id").S(),
				mailAddress(message.Get("from_name"), message.Get("from_address")), Moment(message.Get("sent_at")))
			ctx.Field("To", mailList(message.Get("to")))
			ctx.Field("Cc", mailList(message.Get("cc")))
			ctx.Field("Subject", message.Get("subject").S())
			ctx.Field("Status", mailStatus(message))
			ctx.Field("URL", message.Get("url").S())
			ctx.Blank()

			body, kind := message.Get("body").S(), "text"
			if html {
				body, kind = message.Get("body_html").S(), "HTML"
			}
			if isBlank(body) {
				ctx.Sayf("  (no %s)", kind)
			} else {
				ctx.Paragraph(body, 2)
			}

			attachments := message.Get("attachments").Items()
			if len(attachments) > 0 {
				ctx.Blank()
				ctx.Say("  Attachments:")
				var rows [][]string
				for _, attachment := range attachments {
					rows = append(rows, []string{attachment.Get("filename").S(), Bytes(attachment.Get("file_size")), attachment.Get("download_url").S()})
				}
				ctx.Table(rows, 4)
			}

			for _, invite := range message.Get("calendar_invites").Items() {
				ctx.Blank()
				location := invite.Get("location").S()
				ctx.Sayf("  Invitation: %s, %s to %s%s (%s)", invite.Get("summary").S(), Moment(invite.Get("starts_at")),
					Moment(invite.Get("ends_at")), If(location != "", ", "+location), invite.Get("status").S())
			}
		}
		return nil
	})
}

func readMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, true, "read", func(message string) string { return "Marked " + message + " as read." })
}

func unreadMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, false, "read", func(message string) string { return "Marked " + message + " as unread." })
}

func starMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, true, "star", func(message string) string { return "Starred " + message + "." })
}

func unstarMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, false, "star", func(message string) string { return "Unstarred " + message + "." })
}

func archiveMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, true, "archive", func(message string) string { return "Archived " + message + "." })
}

func unarchiveMail(ctx *Ctx, args *Args) error {
	return changeMail(ctx, args, false, "archive", func(message string) string { return "Unarchived " + message + "." })
}

func moveMail(ctx *Ctx, args *Args) error {
	// `mail list` shows views in lowercase; moving needs the folder names the server uses.
	folder := args.At(1)
	if equalFoldASCII(folder, "inbox") {
		folder = "INBOX"
	}
	if folder == "sent" {
		folder = "Sent"
	}
	if slices.Contains([]string{"drafts", "starred", "archive", "trash"}, folder) {
		hint := ""
		switch folder {
		case "starred":
			hint = "; use `dobase mail star`"
		case "archive":
			hint = "; use `dobase mail archive`"
		}
		return api.Usagef("%s is a view, not a folder%s. Move to INBOX, Sent or a custom folder (see `dobase mail list`).", folder, hint)
	}

	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	message, err := ctx.Post(fmt.Sprintf("/tools/%s/mails/%d/move", tool.Get("id").S(), id), api.Object("folder", folder))
	if err != nil {
		return err
	}
	return ctx.Output(message, func() error {
		ctx.Sayf("Moved %s to %s.", mailDescribe(tool, message), message.Get("folder").S())
		return nil
	})
}

func draftMail(ctx *Ctx, args *Args) error {
	if err := requireMailFlags(args, "to", "subject", "body"); err != nil {
		return err
	}
	tool, err := ctx.Tool(args.At(0), "mail")
	if err != nil {
		return err
	}

	subject, err := ctx.Text(args.Value("subject"))
	if err != nil {
		return err
	}
	body, err := ctx.RichText(args.Value("body"), args.On("html"))
	if err != nil {
		return err
	}
	email := api.Object("to", args.Value("to"), "cc", optionalMailFlag(args, "cc"), "bcc", optionalMailFlag(args, "bcc"), "subject", subject, "body", body)
	draft, err := ctx.Post(fmt.Sprintf("/tools/%s/mails/drafts", tool.Get("id").S()), email)
	if err != nil {
		return err
	}
	err = ctx.Output(draft, func() error {
		ctx.Sayf("Saved draft %s to %s. Send it with: dobase mail send %s --draft %s",
			mailDescribe(tool, draft), mailList(draft.Get("to")), tool.Get("id").S(), draft.Get("id").S())
		return nil
	})
	if err != nil {
		return err
	}
	return openMailDraft(ctx, args, draft)
}

func updateMailDraft(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "draft")
	if err != nil {
		return err
	}

	// Only what was given is sent; an empty --cc or --bcc clears it.
	fields := map[string]any{}
	for _, name := range []string{"to", "cc", "bcc"} {
		if value, ok := args.Flag(name); ok {
			fields[name] = value
		}
	}
	if subject, ok := args.Flag("subject"); ok {
		if fields["subject"], err = ctx.Text(subject); err != nil {
			return err
		}
	}
	if body, ok := args.Flag("body"); ok {
		if fields["body"], err = ctx.RichText(body, args.On("html")); err != nil {
			return err
		}
	}
	if len(fields) == 0 {
		return api.Usagef("Nothing to update. See `dobase help mail`.")
	}

	draft, err := ctx.Patch(fmt.Sprintf("/tools/%s/mails/drafts/%d", tool.Get("id").S(), id), fields)
	if err != nil {
		return err
	}
	err = ctx.Output(draft, func() error {
		ctx.Sayf("Updated draft %s to %s. Send it with: dobase mail send %s --draft %s",
			mailDescribe(tool, draft), mailRecipients(draft), tool.Get("id").S(), draft.Get("id").S())
		return nil
	})
	if err != nil {
		return err
	}
	return openMailDraft(ctx, args, draft)
}

func replyMail(ctx *Ctx, args *Args) error {
	if err := requireMailFlags(args, "body"); err != nil {
		return err
	}
	if err := refuseOpenWithSend(args); err != nil {
		return err
	}
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	conversation, err := ctx.Get(fmt.Sprintf("/tools/%s/mails/%d", tool.Get("id").S(), id))
	if err != nil {
		return err
	}
	original, found := mailMessage(conversation, id)
	if !found {
		return api.Failf("%s/%d is not in its conversation.", tool.Get("id").S(), id)
	}
	if original.Get("draft").Truthy() {
		return api.Failf("%[1]s/%[2]d is a draft. Send it with: dobase mail send %[1]s --draft %[2]d", tool.Get("id").S(), id)
	}

	to, cc := replyRecipients(original, conversation.Get("account", "email_address").S(), args.On("all"))
	if len(to) == 0 {
		return api.Failf("%s/%d has no address to reply to.", tool.Get("id").S(), id)
	}

	body, err := ctx.RichText(args.Value("body"), args.On("html"))
	if err != nil {
		return err
	}
	reply := api.Object(
		"to", strings.Join(to, ", "),
		"cc", strings.Join(cc, ", "),
		"subject", "Re: "+stripReplyPrefix(original.Get("subject").S()),
		"body", body,
		"in_reply_to", original.Get("message_id"),
		// The server quotes it below the text as it was written, like the compose page does
		"quoted_message_id", original.Get("id"),
	)
	if args.On("send") {
		sent, err := ctx.Post(fmt.Sprintf("/tools/%s/mails", tool.Get("id").S()), reply)
		if err != nil {
			return err
		}
		return ctx.Output(sent, func() error {
			ctx.Sayf("Sent %s to %s.", Quoted(sent.Get("subject").S()), mailRecipients(sent))
			return nil
		})
	}
	draft, err := ctx.Post(fmt.Sprintf("/tools/%s/mails/drafts", tool.Get("id").S()), reply)
	if err != nil {
		return err
	}
	err = ctx.Output(draft, func() error {
		ctx.Sayf("Saved reply draft %s to %s. Send it with: dobase mail send %s --draft %s",
			mailDescribe(tool, draft), mailRecipients(draft), tool.Get("id").S(), draft.Get("id").S())
		return nil
	})
	if err != nil {
		return err
	}
	return openMailDraft(ctx, args, draft)
}

func forwardMail(ctx *Ctx, args *Args) error {
	if err := requireMailFlags(args, "to"); err != nil {
		return err
	}
	if err := refuseOpenWithSend(args); err != nil {
		return err
	}
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	original, err := messageInConversation(ctx, tool, id)
	if err != nil {
		return err
	}
	if original.Get("draft").Truthy() {
		return api.Failf("%s/%d is a draft; only sent or received mail can be forwarded.", tool.Get("id").S(), id)
	}

	note := ""
	if body, ok := args.Flag("body"); ok {
		if note, err = ctx.RichText(body, args.On("html")); err != nil {
			return err
		}
	}
	attachmentIDs := []api.Value{}
	for _, attachment := range original.Get("attachments").Items() {
		if !attachment.Get("download_url").IsNull() {
			attachmentIDs = append(attachmentIDs, attachment.Get("id"))
		}
	}

	email := api.Object(
		"to", args.Value("to"),
		"cc", optionalMailFlag(args, "cc"),
		"subject", "Fwd: "+stripReplyPrefix(original.Get("subject").S()),
		"body", note,
		// The server adds it below the note as it was written, with the header block of a forward
		"quoted_message_id", original.Get("id"),
		"forward_attachment_ids", attachmentIDs,
	)
	attached := Count(int64(len(attachmentIDs)), "attachment")
	if args.On("send") {
		sent, err := ctx.Post(fmt.Sprintf("/tools/%s/mails", tool.Get("id").S()), email)
		if err != nil {
			return err
		}
		return ctx.Output(sent, func() error {
			ctx.Sayf("Forwarded %s to %s with %s.", Quoted(sent.Get("subject").S()), mailRecipients(sent), attached)
			return nil
		})
	}
	draft, err := ctx.Post(fmt.Sprintf("/tools/%s/mails/drafts", tool.Get("id").S()), email)
	if err != nil {
		return err
	}
	err = ctx.Output(draft, func() error {
		ctx.Sayf("Saved forward draft %s to %s with %s. Send it with: dobase mail send %s --draft %s",
			mailDescribe(tool, draft), mailRecipients(draft), attached, tool.Get("id").S(), draft.Get("id").S())
		return nil
	})
	if err != nil {
		return err
	}
	return openMailDraft(ctx, args, draft)
}

func mailAttachments(ctx *Ctx, args *Args) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	message, err := messageInConversation(ctx, tool, id)
	if err != nil {
		return err
	}
	chosen := message.Get("attachments").Items()

	if name, ok := args.Flag("name"); ok {
		var exact, loose []api.Value
		for _, attachment := range chosen {
			if attachment.Get("filename").S() == name {
				exact = append(exact, attachment)
			}
			if equalFoldASCII(attachment.Get("filename").S(), name) {
				loose = append(loose, attachment)
			}
		}
		chosen = exact
		if len(exact) == 0 {
			chosen = loose
		}
		if len(chosen) == 0 {
			var names []string
			for _, attachment := range message.Get("attachments").Items() {
				names = append(names, Quoted(attachment.Get("filename").S()))
			}
			list := "none"
			if len(names) > 0 {
				list = strings.Join(names, ", ")
			}
			return api.Failf("%s/%d has no attachment called %s. It has: %s.", tool.Get("id").S(), id, Quoted(name), list)
		}
	}

	if !args.Any("save", "name") {
		return ctx.Output(api.Of(chosen), func() error {
			if len(chosen) == 0 {
				ctx.Sayf("%s has no attachments.", mailDescribe(tool, message))
			}
			var rows [][]string
			for _, attachment := range chosen {
				rows = append(rows, []string{attachment.Get("filename").S(), Bytes(attachment.Get("file_size"))})
			}
			ctx.Table(rows, 0)
			return nil
		})
	}

	if len(chosen) == 0 {
		return api.Failf("%s has no attachments.", mailDescribe(tool, message))
	}
	for _, attachment := range chosen {
		if attachment.Get("download_url").IsNull() {
			return api.Failf("%s isn't stored in Dobase (too big when it was synced).", Quoted(attachment.Get("filename").S()))
		}
	}
	directory, ok := args.Flag("save")
	if !ok {
		directory = "."
	}
	if info, err := os.Stat(directory); err != nil || !info.IsDir() {
		return api.Failf("%s is not a directory.", directory)
	}

	// Decide every path before downloading anything, so nothing is half done
	var destinations []string
	for _, attachment := range chosen {
		destination := unusedPath(directory, attachmentFilename(attachment.Get("filename").S()), destinations)
		if _, err := os.Stat(destination); err == nil && !args.On("force") {
			return api.Failf("%s already exists. Use --force to overwrite it.", destination)
		}
		destinations = append(destinations, destination)
	}

	server, err := ctx.API()
	if err != nil {
		return err
	}
	var saved []api.Value
	for i, attachment := range chosen {
		if _, err := server.Download(attachment.Get("download_url").S(), destinations[i]); err != nil {
			return err
		}
		saved = append(saved, api.Object("id", attachment.Get("id"), "filename", attachment.Get("filename"),
			"file_size", attachment.Get("file_size"), "path", destinations[i]))
	}
	return ctx.Output(api.Of(saved), func() error {
		for _, file := range saved {
			ctx.Sayf("Saved %s (%s) to %s.", file.Get("filename").S(), Bytes(file.Get("file_size")), file.Get("path").S())
		}
		return nil
	})
}

func sendMail(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "mail")
	if err != nil {
		return err
	}

	var request api.Value
	if draft, ok := args.Flag("draft"); ok {
		if args.Any("to", "cc", "bcc", "subject", "body", "html") {
			return api.Usagef("--draft sends the draft as it is saved; leave out --to, --cc, --bcc, --subject, --body and --html.")
		}
		// An id, or TOOL/ID as other commands print it
		id := draft[strings.LastIndex(draft, "/")+1:]
		if !IsDigits(id) || (draft != id && len(draft) <= len(id)+1) {
			return api.Usagef("--draft expects a draft id like 21, got %s.", Quoted(draft))
		}
		draftID, _ := strconv.ParseInt(id, 10, 64)

		conversation, err := ctx.Get(fmt.Sprintf("/tools/%s/mails/%d", tool.Get("id").S(), draftID))
		if err != nil {
			return err
		}
		saved, _ := mailMessage(conversation, draftID)
		if !saved.Get("draft").Truthy() {
			return api.Failf("%s/%d is not a draft.", tool.Get("id").S(), draftID)
		}
		if len(saved.Get("to").Items()) == 0 {
			return api.Failf("Draft %s/%d has no recipients.", tool.Get("id").S(), draftID)
		}

		body := saved.Get("body_html").S()
		if saved.Get("body_html").IsNull() {
			body = EscapeHTML(saved.Get("body").S())
		}
		attachmentIDs := []api.Value{}
		for _, attachment := range saved.Get("attachments").Items() {
			attachmentIDs = append(attachmentIDs, attachment.Get("id"))
		}
		request = api.Object(
			"to", mailList(saved.Get("to")),
			"cc", mailList(saved.Get("cc")),
			"bcc", mailList(saved.Get("bcc")),
			"subject", saved.Get("subject"),
			"body", body,
			"in_reply_to", saved.Get("in_reply_to"),
			"quoted_message_id", saved.Get("quoted_message_id"),
			"draft_id", saved.Get("id"),
			"forward_attachment_ids", attachmentIDs,
		)
	} else {
		if err := requireMailFlags(args, "to", "subject", "body"); err != nil {
			return err
		}
		subject, err := ctx.Text(args.Value("subject"))
		if err != nil {
			return err
		}
		body, err := ctx.RichText(args.Value("body"), args.On("html"))
		if err != nil {
			return err
		}
		request = api.Object(
			"to", args.Value("to"),
			"cc", optionalMailFlag(args, "cc"),
			"bcc", optionalMailFlag(args, "bcc"),
			"subject", subject,
			"body", body,
		)
	}

	sent, err := ctx.Post(fmt.Sprintf("/tools/%s/mails", tool.Get("id").S()), request)
	if err != nil {
		return err
	}
	return ctx.Output(sent, func() error {
		ctx.Sayf("Sent %s to %s.", Quoted(sent.Get("subject").S()), mailRecipients(sent))
		return nil
	})
}

func syncMail(ctx *Ctx, args *Args) error {
	tool, err := ctx.Tool(args.At(0), "mail")
	if err != nil {
		return err
	}
	status, err := ctx.Post(fmt.Sprintf("/tools/%s/sync", tool.Get("id").S()), map[string]any{})
	if err != nil {
		return err
	}
	return ctx.Output(status, func() error {
		synced := "never"
		if !status.Get("last_synced_at").IsNull() {
			synced = Moment(status.Get("last_synced_at"))
		}
		ctx.Sayf("Syncing %s (mail %s) in the background. Last synced: %s.", tool.Get("name").S(), tool.Get("id").S(), synced)
		return nil
	})
}

func mailContacts(ctx *Ctx, args *Args) error {
	query := strings.TrimSpace(args.At(1))
	if utf8.RuneCountInString(query) < 2 {
		return api.Usagef("QUERY needs at least 2 characters.")
	}

	tool, err := ctx.Tool(args.At(0), "mail")
	if err != nil {
		return err
	}
	contacts, err := ctx.Get(fmt.Sprintf("/tools/%s/mails_contacts", tool.Get("id").S()), "q", query)
	if err != nil {
		return err
	}
	return ctx.Output(contacts, func() error {
		if len(contacts.Items()) == 0 {
			ctx.Sayf("Nobody matches %s.", Quoted(args.At(1)))
		}
		for _, contact := range contacts.Items() {
			ctx.Say(mailAddress(contact.Get("name"), contact.Get("email_address")))
		}
		return nil
	})
}

func changeMail(ctx *Ctx, args *Args, add bool, action string, done func(string) string) error {
	tool, id, err := ctx.ToolAndID(args.At(0), "mail", "message")
	if err != nil {
		return err
	}
	path := fmt.Sprintf("/tools/%s/mails/%d/%s", tool.Get("id").S(), id, action)
	var message api.Value
	if add {
		message, err = ctx.Post(path, map[string]any{})
	} else {
		message, err = ctx.Delete(path)
	}
	if err != nil {
		return err
	}
	return ctx.Output(message, func() error {
		ctx.Say(done(mailDescribe(tool, message)))
		return nil
	})
}

// mailMessage is the message with this id in a conversation.
func mailMessage(conversation api.Value, id int64) (api.Value, bool) {
	for _, message := range conversation.Get("messages").Items() {
		if message.Get("id").Int() == id {
			return message, true
		}
	}
	return api.Null, false
}

func messageInConversation(ctx *Ctx, tool api.Value, id int64) (api.Value, error) {
	conversation, err := ctx.Get(fmt.Sprintf("/tools/%s/mails/%d", tool.Get("id").S(), id))
	if err != nil {
		return api.Null, err
	}
	message, found := mailMessage(conversation, id)
	if !found {
		return api.Null, api.Failf("%s/%d is not in its conversation.", tool.Get("id").S(), id)
	}
	return message, nil
}

func refuseOpenWithSend(args *Args) error {
	if args.On("open") && args.On("send") {
		return api.Usagef("--open opens a saved draft; with --send nothing is saved to open.")
	}
	return nil
}

// openMailDraft shows the saved draft with --open, in the installed app or the browser, on the page where it is edited and sent.
func openMailDraft(ctx *Ctx, args *Args, draft api.Value) error {
	if !args.On("open") {
		return nil
	}
	url := draft.Get("url").S()
	if err := ctx.Browser(url); err != nil {
		return api.Failf("The draft is saved, but it didn't open (%v). It is at %s", err, url)
	}
	return nil
}

// attachmentFilename is only the last path segment of a name from the mail, never an empty or dot-only one.
func attachmentFilename(name string) string {
	name = strings.TrimSpace(name[strings.LastIndexAny(name, "/\\")+1:])
	if strings.ReplaceAll(name, ".", "") == "" {
		return "attachment"
	}
	return name
}

// unusedPath is name in directory, numbered like "scan (2).pdf" when another attachment already took it.
func unusedPath(directory, name string, taken []string) string {
	stem, extension := name, ""
	if dot := strings.LastIndex(name, "."); dot > 0 {
		stem, extension = name[:dot], name[dot:]
	}
	// Joined without cleaning, so "." stays in the path as given
	if !strings.HasSuffix(directory, "/") {
		directory += "/"
	}
	for number := 1; ; number++ {
		candidate := name
		if number > 1 {
			candidate = fmt.Sprintf("%s (%d)%s", stem, number, extension)
		}
		if path := directory + candidate; !slices.Contains(taken, path) {
			return path
		}
	}
}

func requireMailFlags(args *Args, names ...string) error {
	var missing []string
	for _, name := range names {
		if _, ok := args.Flag(name); !ok {
			missing = append(missing, "--"+name)
		}
	}
	if len(missing) > 0 {
		return api.Usagef("Missing %s. See `dobase help mail`.", strings.Join(missing, ", "))
	}
	return nil
}

// optionalMailFlag is the flag's value, or null when it wasn't given.
func optionalMailFlag(args *Args, name string) any {
	if value, ok := args.Flag(name); ok {
		return value
	}
	return api.Null
}

// replyRecipients are the to and cc addresses of a reply. Like other mail
// clients, a reply to a message you sent goes to its recipients.
func replyRecipients(message api.Value, ownAddress string, all bool) ([]string, []string) {
	own := func(address string) bool { return equalFoldASCII(address, ownAddress) }
	addresses := func(value api.Value) []string {
		var list []string
		for _, item := range value.Items() {
			list = append(list, item.S())
		}
		return list
	}
	contains := func(list []string, address string) bool {
		return slices.ContainsFunc(list, func(recipient string) bool { return equalFoldASCII(recipient, address) })
	}

	var to []string
	if from := message.Get("from_address"); !from.IsNull() {
		if own(from.S()) {
			to = addresses(message.Get("to"))
		} else {
			to = []string{from.S()}
		}
	}

	var cc []string
	if all {
		for _, address := range append(addresses(message.Get("to")), addresses(message.Get("cc"))...) {
			if !own(address) && !contains(to, address) && !contains(cc, address) {
				cc = append(cc, address)
			}
		}
	}
	return to, cc
}

func stripReplyPrefix(subject string) string {
	for _, prefix := range []string{"re:", "fwd:", "fw:"} {
		if len(subject) >= len(prefix) && equalFoldASCII(subject[:len(prefix)], prefix) {
			return strings.TrimSpace(subject[len(prefix):])
		}
	}
	return strings.TrimSpace(subject)
}

// equalFoldASCII compares ignoring the case of ASCII letters only.
func equalFoldASCII(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		x, y := a[i], b[i]
		if 'A' <= x && x <= 'Z' {
			x += 'a' - 'A'
		}
		if 'A' <= y && y <= 'Z' {
			y += 'a' - 'A'
		}
		if x != y {
			return false
		}
	}
	return true
}

func mailDescribe(tool, message api.Value) string {
	subject := message.Get("subject").S()
	if subject == "" {
		subject = "(no subject)"
	} else {
		subject = Quoted(subject)
	}
	return fmt.Sprintf("%s/%s %s", tool.Get("id").S(), message.Get("id").S(), subject)
}

func mailAddress(name, email api.Value) string {
	if name.S() == "" {
		return email.S()
	}
	return fmt.Sprintf("%s <%s>", name.S(), email.S())
}

func mailList(addresses api.Value) string {
	var list []string
	for _, address := range addresses.Items() {
		list = append(list, address.S())
	}
	return strings.Join(list, ", ")
}

func mailRecipients(email api.Value) string {
	return Join("; ",
		mailList(email.Get("to")),
		If(len(email.Get("cc").Items()) > 0, "cc "+mailList(email.Get("cc"))),
		If(len(email.Get("bcc").Items()) > 0, "bcc "+mailList(email.Get("bcc"))),
	)
}

func mailConversationSummary(conversation api.Value) string {
	messages := conversation.Get("messages_count").Int()
	return Join("  ",
		If(!conversation.Get("read").Truthy(), "unread"),
		If(conversation.Get("starred").Truthy(), "starred"),
		If(messages > 1, Count(messages, "message")),
		If(conversation.Get("has_attachments").Truthy(), "attachments"),
	)
}

func mailStatus(message api.Value) string {
	read := "unread"
	if message.Get("read").Truthy() {
		read = "read"
	}
	return Join(", ",
		If(message.Get("draft").Truthy(), "draft"),
		read,
		If(message.Get("starred").Truthy(), "starred"),
		If(message.Get("archived").Truthy(), "archived"),
		If(message.Get("trashed").Truthy(), "in trash"),
		If(!message.Get("draft").Truthy(), "folder "+message.Get("folder").S()),
	)
}

func mailFolderSummary(mailbox api.Value) string {
	counts := mailbox.Get("counts")
	var names []string
	for _, folder := range mailbox.Get("folders").Items() {
		name := folder.S()
		var number int64
		label := ""
		switch name {
		case "inbox":
			number, label = counts.Get("inbox_unread").Int(), " unread"
		case "drafts":
			number = counts.Get("drafts").Int()
		case "trash":
			number = counts.Get("trash").Int()
		}
		if number > 0 {
			name = fmt.Sprintf("%s (%d%s)", name, number, label)
		}
		names = append(names, name)
	}
	for _, folder := range mailbox.Get("custom_folders").Items() {
		names = append(names, folder.S())
	}
	return strings.Join(names, ", ")
}

// shellEscape quotes a value for a shell command line, like Ruby's Shellwords.escape.
func shellEscape(value string) string {
	if value == "" {
		return "''"
	}
	var escaped strings.Builder
	for _, char := range value {
		switch {
		case char < 0x80 && (('a' <= char && char <= 'z') || ('A' <= char && char <= 'Z') || ('0' <= char && char <= '9')),
			strings.ContainsRune("_-.,:+/@", char), char >= 0x80:
			escaped.WriteRune(char)
		case char == '\n':
			escaped.WriteString("'\n'")
		default:
			escaped.WriteString("\\" + string(char))
		}
	}
	return escaped.String()
}
