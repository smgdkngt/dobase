package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

const mailWithAttachments = `{
	"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
	"/tools/8/mails/310": { "account": { "email_address": "me@example.com" }, "messages": [
		{ "id": 310, "draft": false, "from_name": "Ann <Lee>", "from_address": "ann@example.com", "to": ["me@example.com"],
		  "cc": [], "subject": "Re: Plans", "sent_at": "2026-09-24T14:05:00.000+02:00", "body": "Plan A & B\n\nOK?", "body_html": null,
		  "attachments": [
			{ "id": 51, "filename": "plan.pdf", "file_size": 2048, "download_url": "https://dobase.test/blobs/51/plan.pdf" },
			{ "id": 52, "filename": "../plan.pdf", "file_size": 10, "download_url": "https://dobase.test/blobs/52/plan.pdf" },
			{ "id": 53, "filename": "huge.mov", "file_size": 99, "download_url": null }
		  ] }
	] },
	"/tools/8/mails/311": { "messages": [
		{ "id": 311, "draft": false, "subject": "Scans", "attachments": [
			{ "id": 71, "filename": "../../scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/71" },
			{ "id": 72, "filename": "scan.pdf", "file_size": 1, "download_url": "https://dobase.test/blobs/72" },
			{ "id": 73, "filename": "..", "file_size": 1, "download_url": "https://dobase.test/blobs/73" }
		] }
	] },
	"/tools/8/mails/312": { "messages": [
		{ "id": 312, "draft": true, "to": ["bob@example.com"], "cc": [], "subject": "Fwd: Plans", "body_html": "<p>FYI</p>",
		  "in_reply_to": null, "attachments": [{ "id": 61, "filename": "plan.pdf", "file_size": 2048, "download_url": "https://dobase.test/blobs/61" }] }
	] }
}`

// mailCtx is a context on fake, whose browser records the URLs it opens.
func mailCtx(out *bytes.Buffer, json bool, fake *fakeAPI, opened *[]string) *command.Ctx {
	ctx := command.NewCtx(&config.Config{}, out, json, "test")
	ctx.SetAPI(fake)
	ctx.Browser = func(url string) error {
		*opened = append(*opened, url)
		return nil
	}
	return ctx
}

func TestRepliesSentFromTheCLINameTheMessageTheyAnswer(t *testing.T) {
	var sent []api.Value
	var out bytes.Buffer
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(newFakeAPI(`{
		"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
		"/tools/8/mails/310": { "account": { "email_address": "me@example.com" }, "messages": [
			{ "id": 310, "draft": false, "from_address": "ann@example.com", "to": ["me@example.com", "bob@example.com"],
			  "cc": ["ANN@example.com", "cy@example.com"], "subject": "Re: Plans", "message_id": "plans@example.com" }
		] },
		"/tools/8/mails/312": { "messages": [
			{ "id": 312, "draft": true, "to": ["ann@example.com"], "cc": [], "subject": "Re: Plans",
			  "body_html": "<p>Yes</p>", "in_reply_to": "plans@example.com" }
		] }
	}`, &sent))

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--send", "--all"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail send", "8", "--draft", "312"); err != nil {
		t.Fatal(err)
	}

	for _, email := range sent {
		if got := email.Get("in_reply_to").S(); got != "plans@example.com" {
			t.Errorf("in_reply_to %q", got)
		}
	}
	for key, want := range map[string]string{"to": "ann@example.com", "cc": "bob@example.com, cy@example.com", "subject": "Re: Plans"} {
		if got := sent[0].Get(key).S(); got != want {
			t.Errorf("%s: got %q", key, got)
		}
	}
	if got := sent[0].Get("body").S(); !strings.HasPrefix(got, "<p>Sure</p><p>On , ann@example.com wrote:</p><blockquote>") {
		t.Errorf("body %q", got)
	}
	if got := sent[1].Get("draft_id").JSON(); got != "312" {
		t.Errorf("draft_id %s", got)
	}
	if !strings.Contains(out.String(), `Sent "Re: Plans" to ann@example.com.`) {
		t.Errorf("out %q", out.String())
	}
}

func TestForwardsQuoteTheOriginalAndCarryItsStoredAttachments(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)

	if err := invoke(ctx, "mail forward", "8/310", "--to", "bob@example.com", "--body", "See below", "--open"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail send", "8", "--draft", "312"); err != nil {
		t.Fatal(err)
	}

	if want := []string{"/tools/8/mails/drafts", "/tools/8/mails"}; !slices.Equal(fake.paths, want) {
		t.Errorf("paths %v", fake.paths)
	}
	if got := sent[0].Get("to").S(); got != "bob@example.com" {
		t.Errorf("to %q", got)
	}
	if got := sent[0].Get("subject").S(); got != "Fwd: Plans" {
		t.Errorf("subject %q", got)
	}
	if got := sent[0].Get("forward_attachment_ids").JSON(); got != "[51,52]" {
		t.Errorf("forward_attachment_ids %s", got)
	}
	want := "<p>See below</p><br><br><p>---------- Forwarded message ----------<br>From: Ann &lt;Lee&gt; &lt;ann@example.com&gt;<br>" +
		"Date: Thu, Sep 24, 2026 at 2:05 PM<br>Subject: Re: Plans<br>To: me@example.com</p><p>Plan A &amp; B</p><p>OK?</p>"
	if got := sent[0].Get("body").S(); got != want {
		t.Errorf("body %q", got)
	}
	if want := []string{"https://dobase.test/tools/8/mails/new?draft_id=400"}; !slices.Equal(opened, want) {
		t.Errorf("opened %v", opened)
	}
	if got := sent[1].Get("forward_attachment_ids").JSON(); got != "[61]" {
		t.Errorf("forward_attachment_ids %s", got)
	}
	if !strings.Contains(out.String(), `Saved forward draft 8/400 "Fwd: Plans" to ann@example.com with 2 attachments.`) {
		t.Errorf("out %q", out.String())
	}
}

func TestRepliesQuoteTheMessageTheyAnswer(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	responses := api.MustParse(mailWithAttachments).With("/tools/8/mails/313", api.MustParse(`{ "account": { "email_address": "me@example.com" }, "messages": [
		{ "id": 313, "draft": false, "from_name": "", "from_address": "bob@example.com", "to": ["me@example.com"], "cc": [],
		  "subject": "Lunch", "sent_at": "2026-09-25T12:30:00.000+02:00", "body": "Lunch?", "body_html": "<div>Lunch <b>today</b>?</div>" }
	] }`))
	ctx := mailCtx(&out, false, newFakeAPI(responses.JSON(), &sent), &opened)

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Plan B.\n\nSee you then."); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail reply", "8/313", "--body", "<p>Yes</p><ul><li>12:30</li></ul>", "--html"); err != nil {
		t.Fatal(err)
	}

	want := "<p>Plan B.</p><p>See you then.</p><p>On Thu, Sep 24, 2026 at 2:05 PM, Ann &lt;Lee&gt; &lt;ann@example.com&gt; wrote:</p>" +
		"<blockquote><p>Plan A &amp; B</p><p>OK?</p></blockquote>"
	if got := sent[0].Get("body").S(); got != want {
		t.Errorf("body %q", got)
	}
	want = "<p>Yes</p><ul><li>12:30</li></ul><p>On Fri, Sep 25, 2026 at 12:30 PM, bob@example.com wrote:</p>" +
		"<blockquote><div>Lunch <b>today</b>?</div></blockquote>"
	if got := sent[1].Get("body").S(); got != want {
		t.Errorf("body %q", got)
	}
}

func TestOpenIsOnlyForDrafts(t *testing.T) {
	for _, args := range [][]string{
		{"mail", "forward", "8/310", "--to", "a@example.com", "--send", "--open"},
		{"mail", "reply", "8/310", "--body", "Hi", "--send", "--open"},
	} {
		status, _, err := run(args...)
		if status != 2 || !strings.Contains(err, "--open opens a saved draft") {
			t.Errorf("%v: status %d, err %q", args, status, err)
		}
	}
}

func TestAttachmentsAreListedAndSavedUnderTheirOwnNames(t *testing.T) {
	directory := t.TempDir()
	var sent []api.Value
	var opened []string

	var out bytes.Buffer
	ctx := mailCtx(&out, true, newFakeAPI(mailWithAttachments, &sent), &opened)
	if err := invoke(ctx, "mail attachments", "8/310"); err != nil {
		t.Fatal(err)
	}
	if listed := api.MustParse(out.String()); len(listed.Items()) != 3 {
		t.Errorf("listed %s", out.String())
	}

	// huge.mov was never stored, so saving everything fails before anything is downloaded
	out.Reset()
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx = mailCtx(&out, false, fake, &opened)
	failed := func(argv ...string) {
		t.Helper()
		if err := invoke(ctx, "mail attachments", argv...); err == nil || api.KindOf(err) != api.Failed {
			t.Errorf("%v: %v", argv, err)
		}
	}
	failed("8/310", "--save", directory)
	if len(fake.paths) > 0 {
		t.Errorf("downloaded %v", fake.paths)
	}

	if err := invoke(ctx, "mail attachments", "8/310", "--save", directory, "--name", "PLAN.PDF"); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(directory, "plan.pdf")); string(data) != "data from https://dobase.test/blobs/51/plan.pdf" {
		t.Errorf("plan.pdf holds %q", data)
	}
	failed("8/310", "--save", directory, "--name", "plan.pdf")
	failed("8/310", "--name", "nope.txt")

	// Names from the mail stay inside the directory, and the same name twice gets a number
	if err := invoke(ctx, "mail attachments", "8/311", "--save", directory); err != nil {
		t.Fatal(err)
	}
	for name, blob := range map[string]string{"scan.pdf": "71", "scan (2).pdf": "72", "attachment": "73"} {
		if data, _ := os.ReadFile(filepath.Join(directory, name)); string(data) != "data from https://dobase.test/blobs/"+blob {
			t.Errorf("%s holds %q", name, data)
		}
	}
	if want := "Saved plan.pdf (2.0 KB) to " + directory + "/plan.pdf."; !strings.Contains(out.String(), want) {
		t.Errorf("out %q", out.String())
	}
}
