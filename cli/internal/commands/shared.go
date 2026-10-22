package commands

import (
	"os"
	"strconv"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

// showDetails prints the description, comments and attachments of a card or todo.
func showDetails(ctx *Ctx, record api.Value) {
	if description := record.Get("description").S(); !isBlank(description) {
		ctx.Blank()
		ctx.Say("Description:")
		ctx.Paragraph(description, 2)
	}

	comments := record.Get("comments").Items()
	ctx.Blank()
	ctx.Sayf("Comments (%d):", len(comments))
	for _, comment := range comments {
		ctx.Sayf("  %s · %s [comment %s]", Poster(comment, "Former member"), Moment(comment.Get("created_at")), comment.Get("id").S())
		ctx.Paragraph(comment.Get("body").S(), 4)
	}

	attachments := record.Get("attachments").Items()
	if len(attachments) > 0 {
		ctx.Blank()
		ctx.Sayf("Attachments (%d):", len(attachments))
		var rows [][]string
		for _, attachment := range attachments {
			rows = append(rows, []string{attachment.Get("filename").S(), Bytes(attachment.Get("file_size")), attachment.Get("download_url").S()})
		}
		ctx.Table(rows, 2)
	}
}

// deleteComment deletes a comment, by the id `show` prints, with tool (card_uncomment,
// todo_uncomment) and what it was on in args. label is what it was on: "card 12/104".
func deleteComment(ctx *Ctx, tool string, args map[string]any, comment, label string) error {
	if !IsDigits(comment) {
		return api.Usagef("Expected a comment id like 77, got %s. `show` prints them as [comment ID].", Quoted(comment))
	}
	id, _ := strconv.ParseInt(comment, 10, 64)
	args["comment_id"] = id
	args["confirm"] = true
	if _, err := ctx.Call(tool, args); err != nil {
		return err
	}
	return ctx.Output(api.Null, func() error {
		ctx.Sayf("Deleted comment %s from %s.", comment, label)
		return nil
	})
}

// position turns "3" (1 = top) into a tool's position, which counts the same way.
func position(text string) int64 {
	n, _ := strconv.ParseInt(strings.TrimSpace(text), 10, 64)
	return max(n, 1)
}

// asToolArgs turns a card's or todo's attributes, as the API names them, into
// what card_create, card_update, todo_create and todo_update take: the text is
// HTML already, and what clears a field is "none".
func asToolArgs(attributes map[string]any) map[string]any {
	args := map[string]any{}
	none := func(value any) any {
		if v, ok := value.(api.Value); ok {
			if v.IsNull() {
				return "none"
			}
			return v.S()
		}
		if value == nil || value == "" {
			return "none"
		}
		return value
	}
	for name, value := range attributes {
		switch name {
		case "description":
			args["description"], args["html"] = value, true
		case "due_date":
			args["due"] = none(value)
		case "assigned_user_id":
			args["assignee"] = none(value)
		case "color", "recurrence_rule":
			key := map[string]string{"color": "color", "recurrence_rule": "repeat"}[name]
			args[key] = none(value)
		default:
			args[name] = value
		}
	}
	return args
}

// toolArgs are a tool's arguments, leaving out what wasn't given (null).
func toolArgs(pairs ...any) map[string]any {
	args := map[string]any{}
	for i := 0; i+1 < len(pairs); i += 2 {
		if value, ok := pairs[i+1].(api.Value); ok && value.IsNull() {
			continue
		}
		if pairs[i+1] == nil {
			continue
		}
		args[pairs[i].(string)] = pairs[i+1]
	}
	return args
}

// attachFiles uploads each file as an attachment to path, one request per file.
func attachFiles(ctx *Ctx, path string, files []string, label string) error {
	var missing []string
	for _, file := range files {
		if info, err := os.Stat(file); err != nil || !info.Mode().IsRegular() {
			missing = append(missing, file)
		}
	}
	if len(missing) > 0 {
		return api.Usagef("No such file: %s", strings.Join(missing, ", "))
	}

	server, err := ctx.API()
	if err != nil {
		return err
	}
	var attachments []api.Value
	for _, file := range files {
		attachment, err := server.Upload(path, []api.FilePart{{Field: "file", Path: file}}, nil)
		if err != nil {
			return err
		}
		attachments = append(attachments, attachment)
	}
	return ctx.Output(api.Of(attachments), func() error {
		for _, attachment := range attachments {
			ctx.Sayf("Attached %s (%s) to %s.", attachment.Get("filename").S(), Bytes(attachment.Get("file_size")), label)
		}
		return nil
	})
}

// filesToAttach are the files --attach names, as parts of a form under field,
// checked before anything is saved or sent.
func filesToAttach(args *Args, field string) ([]api.FilePart, error) {
	var files []api.FilePart
	for _, path := range args.All("attach") {
		info, err := os.Stat(path)
		if err != nil {
			return nil, api.PathError(path, err)
		}
		if info.IsDir() {
			return nil, api.Failf("%s is a directory. Attach files one by one.", path)
		}
		files = append(files, api.FilePart{Field: field, Path: path})
	}
	return files, nil
}

// findNamed finds a column, list or calendar by id, name, or the start of its
// name. Without a reference ("") it's the first one.
func findNamed(items []api.Value, reference, key, what, plural, owner string) (api.Value, error) {
	if reference == "" {
		if len(items) == 0 {
			return api.Null, api.Failf("%s has no %ss.", owner, what)
		}
		return items[0], nil
	}

	lower := strings.ToLower(reference)
	for _, match := range []func(api.Value) bool{
		func(item api.Value) bool { return item.Get("id").S() == reference },
		func(item api.Value) bool { return strings.ToLower(item.Get(key).S()) == lower },
		func(item api.Value) bool { return strings.HasPrefix(strings.ToLower(item.Get(key).S()), lower) },
	} {
		for _, item := range items {
			if match(item) {
				return item, nil
			}
		}
	}
	names := make([]string, len(items))
	for i, item := range items {
		names[i] = item.Get(key).S()
	}
	return api.Null, api.Failf("No %s matches %s. %s: %s", what, Quoted(reference), plural, strings.Join(names, ", "))
}
