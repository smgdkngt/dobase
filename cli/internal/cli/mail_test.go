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
	if got := sent[0].Get("body").S(); got != "<p>Sure</p>" {
		t.Errorf("body %q", got)
	}
	if got := sent[0].Get("quoted_message_id").JSON(); got != "310" {
		t.Errorf("quoted_message_id %s", got)
	}
	if got := sent[1].Get("draft_id").JSON(); got != "312" {
		t.Errorf("draft_id %s", got)
	}
	if !strings.Contains(out.String(), `Sent "Re: Plans" to ann@example.com.`) {
		t.Errorf("out %q", out.String())
	}
}

func TestForwardsNameTheOriginalAndCarryItsStoredAttachments(t *testing.T) {
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
	// The server adds the forwarded mail below the note
	if got := sent[0].Get("body").S(); got != "<p>See below</p>" {
		t.Errorf("body %q", got)
	}
	if got := sent[0].Get("quoted_message_id").JSON(); got != "310" {
		t.Errorf("quoted_message_id %s", got)
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

func TestRepliesLeaveTheQuoteToTheServer(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	ctx := mailCtx(&out, false, newFakeAPI(mailWithAttachments, &sent), &opened)

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Plan B.\n\nSee you then."); err != nil {
		t.Fatal(err)
	}

	if got := sent[0].Get("body").S(); got != "<p>Plan B.</p><p>See you then.</p>" {
		t.Errorf("body %q", got)
	}
	if got := sent[0].Get("quoted_message_id").JSON(); got != "310" {
		t.Errorf("quoted_message_id %s", got)
	}
}

func TestAQuoteIsChangedOrLeftOutWhereFlagsSay(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)
	changed := `<p>Ann wrote:</p><blockquote type="cite"><p>Plan A</p></blockquote>`

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--quote", changed); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--no-quote", "--send"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail forward", "8/310", "--to", "bob@example.com", "--quote", changed); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail update", "8/312", "--quote", changed); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail update", "8/312", "--no-quote"); err != nil {
		t.Fatal(err)
	}

	if want := []string{"POST /tools/8/mails/drafts", "POST /tools/8/mails", "POST /tools/8/mails/drafts",
		"PATCH /tools/8/mails/drafts/312", "PATCH /tools/8/mails/drafts/312"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	// The quote as given, of the mail it still answers
	for _, index := range []int{0, 2} {
		if got := sent[index].Get("quoted_message_id").JSON() + " " + sent[index].Get("quote_html").S(); got != "310 "+changed {
			t.Errorf("request %d: %s", index, got)
		}
	}
	// Nothing is quoted, and the reply still has what a reply has
	if got := sent[1].Get("quoted_message_id").JSON() + " " + sent[1].Get("subject").S(); got != "null Re: Plans" || sent[1].Has("quote_html") {
		t.Errorf("reply without a quote: %s", sent[1].JSON())
	}
	if got := sent[3].JSON(); got != `{"quote_html":"<p>Ann wrote:</p><blockquote type=\"cite\"><p>Plan A</p></blockquote>"}` {
		t.Errorf("update: %s", got)
	}
	if got := sent[4].JSON(); got != `{"quoted_message_id":null}` {
		t.Errorf("update: %s", got)
	}

	for _, flags := range [][]string{{"--quote", changed, "--no-quote"}, {"--quote", "-", "--body", "-"}, {"--quote", " "}} {
		if err := invoke(ctx, "mail update", append([]string{"8/312"}, flags...)...); api.KindOf(err) != api.Usage {
			t.Errorf("%v: got %v", flags, err)
		}
	}
	if len(sent) != 5 {
		t.Errorf("%d requests", len(sent))
	}
}

func TestADraftShowsWhatItQuotes(t *testing.T) {
	var out bytes.Buffer
	ctx := mailCtx(&out, false, newFakeAPI(`{
		"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
		"/tools/8/mails/312": { "subject": "Re: Plans", "messages": [
			{ "id": 312, "draft": true, "to": ["ann@example.com"], "cc": [], "subject": "Re: Plans", "body": "Sure", "body_html": "<p>Sure</p>",
			  "quote": "Ann wrote:\n\n> Plan A", "quote_html": "<p>Ann wrote:</p><blockquote><p>Plan A</p></blockquote>", "attachments": [] }
		] }
	}`, nil), nil)

	if err := invoke(ctx, "mail show", "8/312"); err != nil {
		t.Fatal(err)
	}
	if want := "  Sure\n\n  Quoted below it:\n    Ann wrote:\n\n    > Plan A\n"; !strings.Contains(out.String(), want) {
		t.Errorf("out %q", out.String())
	}

	out.Reset()
	if err := invoke(ctx, "mail show", "8/312", "--html"); err != nil {
		t.Fatal(err)
	}
	if want := "    <p>Ann wrote:</p><blockquote><p>Plan A</p></blockquote>"; !strings.Contains(out.String(), want) {
		t.Errorf("out %q", out.String())
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

func TestSendingADraftKeepsItsBcc(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	ctx := mailCtx(&out, false, newFakeAPI(`{
		"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
		"/tools/8/mails/312": { "messages": [
			{ "id": 312, "draft": true, "to": ["ann@example.com"], "cc": ["bob@example.com"],
			  "bcc": ["boss@example.com", "audit@example.com"], "subject": "Offer", "body_html": "<p>Yes</p>" }
		] },
		"/tools/8/mails/313": { "messages": [
			{ "id": 313, "draft": true, "to": ["ann@example.com"], "cc": [], "bcc": [], "subject": "Offer", "body_html": "<p>Yes</p>" }
		] }
	}`, &sent), &opened)

	for _, draft := range []string{"312", "313"} {
		if err := invoke(ctx, "mail send", "8", "--draft", draft); err != nil {
			t.Fatal(err)
		}
	}
	if got := sent[0].Get("bcc").S(); got != "boss@example.com, audit@example.com" {
		t.Errorf("bcc %q", got)
	}
	if got := sent[0].Get("cc").S(); got != "bob@example.com" {
		t.Errorf("cc %q", got)
	}
	if got := sent[1].Get("bcc").S(); got != "" {
		t.Errorf("bcc of a draft without one: %q", got)
	}
}

func TestADraftIsChangedOnlyWhereFlagsSay(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)

	if err := invoke(ctx, "mail update", "8/312", "--subject", "Plans, again", "--bcc", "boss@example.com", "--cc", "", "--body", "Hi\n\nBye", "--open"); err != nil {
		t.Fatal(err)
	}
	if want := []string{"PATCH /tools/8/mails/drafts/312"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].JSON(); got != `{"bcc":"boss@example.com","body":"<p>Hi</p><p>Bye</p>","cc":"","subject":"Plans, again"}` {
		t.Errorf("sent %s", got)
	}
	if want := []string{"https://dobase.test/tools/8/mails/new?draft_id=400"}; !slices.Equal(opened, want) {
		t.Errorf("opened %v", opened)
	}
	if want := `Updated draft 8/400 "Plans, again" to ann@example.com. Send it with: dobase mail send 8 --draft 400`; !strings.Contains(out.String(), want) {
		t.Errorf("out %q", out.String())
	}

	if err := invoke(ctx, "mail update", "8/312"); api.KindOf(err) != api.Usage || !strings.Contains(err.Error(), "Nothing to update") {
		t.Errorf("got %v", err)
	}

	// A new draft can have a Bcc too
	if err := invoke(ctx, "mail draft", "8", "--to", "ann@example.com", "--bcc", "boss@example.com", "--subject", "Hi", "--body", "Hi"); err != nil {
		t.Fatal(err)
	}
	if got := sent[1].Get("bcc").S(); got != "boss@example.com" {
		t.Errorf("bcc %q", got)
	}
}

func TestFilesAreAttachedToTheSavedDraft(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)

	directory := t.TempDir()
	offer, terms := filepath.Join(directory, "offer.pdf"), filepath.Join(directory, "terms.pdf")
	for _, path := range []string{offer, terms} {
		if err := os.WriteFile(path, []byte("pdf"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	if err := invoke(ctx, "mail draft", "8", "--to", "ann@example.com", "--subject", "Plans", "--body", "Hi", "--attach", offer, "--attach", terms); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--attach="+offer, "--open"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail forward", "8/310", "--to", "bob@example.com", "--attach", terms); err != nil {
		t.Fatal(err)
	}
	// Attaching alone leaves the rest of the draft as it is
	if err := invoke(ctx, "mail update", "8/312", "--attach", offer); err != nil {
		t.Fatal(err)
	}

	if want := []string{"POST /tools/8/mails/drafts", "POST /tools/8/mails/drafts", "POST /tools/8/mails/drafts"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if want := []string{
		"/tools/8/mails/drafts/400/attachments: files[]=offer.pdf, files[]=terms.pdf",
		"/tools/8/mails/drafts/400/attachments: files[]=offer.pdf",
		"/tools/8/mails/drafts/400/attachments: files[]=terms.pdf",
		"/tools/8/mails/drafts/312/attachments: files[]=offer.pdf",
	}; !slices.Equal(fake.uploads, want) {
		t.Errorf("uploads %v", fake.uploads)
	}
	for _, want := range []string{
		`Saved draft 8/400 "Plans" to ann@example.com with 2 attachments. Send it`,
		`Saved reply draft 8/400 "Plans" to ann@example.com with 1 attachment. Send it`,
		`Saved forward draft 8/400 "Plans" to ann@example.com with 3 attachments. Send it`,
		`Updated draft 8/400 "Plans" to ann@example.com with 1 attachment. Send it`,
	} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("no %q in %q", want, out.String())
		}
	}
	if len(opened) != 1 {
		t.Errorf("opened %v", opened)
	}
}

func TestAMissingFileStopsTheDraftBeforeItIsSaved(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)
	directory := t.TempDir()

	for _, path := range []string{filepath.Join(directory, "missing.pdf"), directory} {
		for _, command := range [][]string{
			{"mail draft", "8", "--to", "ann@example.com", "--subject", "Plans", "--body", "Hi", "--attach", path},
			{"mail reply", "8/310", "--body", "Sure", "--send", "--attach", path},
			{"mail forward", "8/310", "--to", "bob@example.com", "--attach", path},
			{"mail update", "8/312", "--subject", "Plans", "--attach", path},
		} {
			if err := invoke(ctx, command[0], command[1:]...); err == nil || !strings.Contains(err.Error(), path) {
				t.Errorf("%s: got %v", command[0], err)
			}
		}
	}
	if len(fake.requests) > 0 || len(fake.uploads) > 0 {
		t.Errorf("requests %v, uploads %v", fake.requests, fake.uploads)
	}
}

func TestADraftThatCouldNotTakeItsFilesIsStillThere(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	fake.errors = map[string]error{"/tools/8/mails/drafts/400/attachments": api.Failf("A draft's attachments can be 25 MB together (HTTP 422)")}
	ctx := mailCtx(&out, false, fake, &opened)
	big := filepath.Join(t.TempDir(), "big.zip")
	if err := os.WriteFile(big, []byte("zip"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--send", "--attach", big)

	if err == nil || !strings.Contains(err.Error(), "Draft 8/400 is saved, but nothing was attached to it: A draft's attachments can be 25 MB together") {
		t.Errorf("got %v", err)
	}
	// Nothing went out without its attachment
	if want := []string{"POST /tools/8/mails/drafts"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
}

func TestSendingWithAttachmentsGoesThroughADraftThatHasThem(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)
	offer := filepath.Join(t.TempDir(), "offer.pdf")
	if err := os.WriteFile(offer, []byte("pdf"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--send", "--attach", offer); err != nil {
		t.Fatal(err)
	}

	if want := []string{"POST /tools/8/mails/drafts", "POST /tools/8/mails"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[1].Get("draft_id").JSON() + " " + sent[1].Get("forward_attachment_ids").JSON(); got != "400 [900]" {
		t.Errorf("draft and attachments %s", got)
	}
	for _, key := range []string{"to", "subject", "body", "in_reply_to", "quoted_message_id"} {
		if !sent[1].Get(key).Equal(sent[0].Get(key)) {
			t.Errorf("%s: sent %s, saved %s", key, sent[1].Get(key).JSON(), sent[0].Get(key).JSON())
		}
	}
	if !strings.Contains(out.String(), `Sent "Re: Plans" to ann@example.com with 1 attachment.`) {
		t.Errorf("out %q", out.String())
	}
}

func TestTrashIsItsOwnCommandAndADraftIsDiscardedByItself(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	fake.errors = map[string]error{"/tools/8/mails/310/move": &api.Error{Message: "Invalid folder name (HTTP 422)", Status: 422}}
	ctx := mailCtx(&out, false, fake, &opened)

	// The server's trash is no folder to move to, whatever the server calls it
	err := invoke(ctx, "mail move", "8/310", "Deleted Messages")
	if err == nil || !strings.Contains(err.Error(), "dobase mail trash") {
		t.Errorf("got %v", err)
	}
	if err := invoke(ctx, "mail move", "8/310", "trash"); api.KindOf(err) != api.Usage || !strings.Contains(err.Error(), "dobase mail trash") {
		t.Errorf("got %v", err)
	}

	for _, command := range [][]string{{"mail trash", "8/310"}, {"mail trash", "8/310", "--folder", "Receipts"}, {"mail restore", "8/310"}, {"mail discard", "8/312"}} {
		if err := invoke(ctx, command[0], command[1:]...); err != nil {
			t.Fatal(err)
		}
	}
	// Only a draft is discarded
	if err := invoke(ctx, "mail discard", "8/310"); err == nil || !strings.Contains(err.Error(), "is not a draft") {
		t.Errorf("got %v", err)
	}

	if want := []string{"POST /tools/8/mails/310/trash", "POST /tools/8/mails/310/trash", "DELETE /tools/8/mails/310/trash", "POST /tools/8/mails/312/trash"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[1].Get("folder").S(); got != "Receipts" {
		t.Errorf("folder %q", got)
	}
	if !strings.Contains(out.String(), "Discarded draft 8/400") || !strings.Contains(out.String(), "dobase mail restore 8/400") {
		t.Errorf("out %q", out.String())
	}
}
