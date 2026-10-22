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

// mailFake is fakeAPI with what the server's mail tools work out themselves and
// answer with: the subject of a reply or forward, and of what mail_send sent.
type mailFake struct {
	*fakeAPI
	subjects map[string]string
}

func (m *mailFake) Call(tool string, args map[string]any) (api.Value, error) {
	value, err := m.fakeAPI.Call(tool, args)
	if subject, ok := m.subjects[tool]; ok && err == nil {
		value = value.With("subject", subject)
	}
	return value, err
}

// askedFake is fakeAPI that also keeps every call, reads too, as "tool {args}".
type askedFake struct {
	*fakeAPI
	asked []string
}

func (a *askedFake) Call(tool string, args map[string]any) (api.Value, error) {
	a.asked = append(a.asked, tool+" "+api.Of(args).JSON())
	return a.fakeAPI.Call(tool, args)
}

func TestMailIsListedSyncedAndSearchedWithTheToolsArguments(t *testing.T) {
	var sent []api.Value
	var out bytes.Buffer
	fake := &askedFake{fakeAPI: newFakeAPI(`{
		"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
		"/tools/8/mails": { "account": { "email_address": "me@example.com" }, "folder": "Receipts", "conversations": [] },
		"/tools/8/mails_contacts": [{ "name": "Ann Lee", "email_address": "ann@example.com" }]
	}`, &sent)}
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(fake)

	for _, argv := range [][]string{{"mail list", "8"}, {"mail list", "8", "--folder", "Receipts", "--search", "", "--page", "2"}, {"mail sync", "8"}, {"mail contacts", "8", "an"}} {
		if err := invoke(ctx, argv[0], argv[1:]...); err != nil {
			t.Fatal(err)
		}
	}
	want := []string{
		`tool_list {}`, `mail_list {"tool_id":8}`,
		// Given flags go along even when empty
		`mail_list {"folder":"Receipts","page":2,"query":"","tool_id":8}`,
		`mail_sync {"tool_id":8}`,
		`mail_contacts {"query":"an","tool_id":8}`,
	}
	if !slices.Equal(fake.asked, want) {
		t.Errorf("asked %v", fake.asked)
	}
	if !strings.Contains(out.String(), "Ann Lee <ann@example.com>") {
		t.Errorf("out %q", out.String())
	}
}

// mailCtx is a context on fake, whose browser records the URLs it opens.
func mailCtx(out *bytes.Buffer, json bool, fake api.API, opened *[]string) *command.Ctx {
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
	fake := newFakeAPI(`{
		"/tools": [{ "id": 8, "name": "Inbox", "type": "mail" }],
		"/tools/8/mails/310": { "account": { "email_address": "me@example.com" }, "messages": [
			{ "id": 310, "draft": false, "from_address": "ann@example.com", "to": ["me@example.com", "bob@example.com"],
			  "cc": ["ANN@example.com", "cy@example.com"], "subject": "Re: Plans", "message_id": "plans@example.com" }
		] },
		"/tools/8/mails/312": { "messages": [
			{ "id": 312, "draft": true, "to": ["ann@example.com"], "cc": [], "subject": "Re: Plans",
			  "body_html": "<p>Yes</p>", "in_reply_to": "plans@example.com" }
		] },
		"/tools/8/mails/313": { "account": { "email_address": "me@example.com" }, "messages": [
			{ "id": 313, "draft": false, "from_address": "me@example.com", "to": [], "cc": [], "subject": "Notes" }
		] }
	}`, &sent)
	ctx.SetAPI(&mailFake{fake, map[string]string{"mail_send": "Re: Plans"}})

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--send", "--all"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail send", "8", "--draft", "312"); err != nil {
		t.Fatal(err)
	}

	// mail_reply saves the reply in the conversation (addresses, subject, In-Reply-To and the
	// quote are the server's to work out, as for the compose page), and --send sends that draft
	if want := []string{"mail_reply", "mail_send", "mail_send"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].JSON(); got != `{"all":true,"body":"<p>Sure</p>","html":true,"mail_id":310,"tool_id":8}` {
		t.Errorf("reply %s", got)
	}
	if got := sent[1].JSON() + " " + sent[2].JSON(); got != `{"confirm":true,"draft_id":400,"tool_id":8} {"confirm":true,"draft_id":312,"tool_id":8}` {
		t.Errorf("sent %s", got)
	}
	if strings.Count(out.String(), `Sent "Re: Plans" to ann@example.com.`) != 2 {
		t.Errorf("out %q", out.String())
	}

	// A reply needs someone to go to, which the CLI says before anything is saved
	if err := invoke(ctx, "mail reply", "8/313", "--body", "Hi"); err == nil || err.Error() != "8/313 has no address to reply to." {
		t.Errorf("got %v", err)
	}
	if len(sent) != 3 {
		t.Errorf("%d requests", len(sent))
	}
}

func TestForwardsNameTheOriginalAndCarryItsStoredAttachments(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, &mailFake{fake, map[string]string{"mail_forward": "Fwd: Plans"}}, &opened)

	if err := invoke(ctx, "mail forward", "8/310", "--to", "bob@example.com", "--body", "See below", "--open"); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "mail send", "8", "--draft", "312"); err != nil {
		t.Fatal(err)
	}

	if want := []string{"mail_forward", "mail_send"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	// The server adds the forwarded mail below the note, with its stored attachments (51 and 52; 53 was never stored)
	if got := sent[0].JSON(); got != `{"body":"<p>See below</p>","html":true,"mail_id":310,"to":"bob@example.com","tool_id":8}` {
		t.Errorf("forward %s", got)
	}
	if want := []string{"https://dobase.test/tools/8/mails/new?draft_id=400"}; !slices.Equal(opened, want) {
		t.Errorf("opened %v", opened)
	}
	// A saved draft is sent as it is, with the attachments it has
	if got := sent[1].JSON(); got != `{"confirm":true,"draft_id":312,"tool_id":8}` {
		t.Errorf("send %s", got)
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
	// Nothing said about the quote: the server quotes the mail as it was written
	if got := sent[0].JSON(); got != `{"all":false,"body":"<p>Plan B.</p><p>See you then.</p>","html":true,"mail_id":310,"tool_id":8}` {
		t.Errorf("reply %s", got)
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

	if want := []string{"mail_reply", "mail_reply", "mail_send", "mail_forward", "mail_update", "mail_update"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	// The quote as given, of the mail it still answers
	for _, index := range []int{0, 3} {
		if got := sent[index].Get("mail_id").JSON() + " " + sent[index].Get("quote_html").S(); got != "310 "+changed {
			t.Errorf("request %d: %s", index, got)
		}
	}
	// Nothing is quoted, and the reply still is one
	if got := sent[1].JSON(); got != `{"all":false,"body":"<p>Sure</p>","html":true,"mail_id":310,"no_quote":true,"tool_id":8}` {
		t.Errorf("reply without a quote: %s", got)
	}
	if got := sent[4].JSON(); got != `{"draft_id":312,"quote_html":"<p>Ann wrote:</p><blockquote type=\"cite\"><p>Plan A</p></blockquote>","tool_id":8}` {
		t.Errorf("update: %s", got)
	}
	if got := sent[5].JSON(); got != `{"draft_id":312,"no_quote":true,"tool_id":8}` {
		t.Errorf("update: %s", got)
	}

	for _, flags := range [][]string{{"--quote", changed, "--no-quote"}, {"--quote", "-", "--body", "-"}, {"--quote", " "}} {
		if err := invoke(ctx, "mail update", append([]string{"8/312"}, flags...)...); api.KindOf(err) != api.Usage {
			t.Errorf("%v: got %v", flags, err)
		}
	}
	if len(sent) != 6 {
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
	// mail_send sends the saved draft as it is, Cc and Bcc included: nothing of it goes through the CLI
	if got := sent[0].JSON() + " " + sent[1].JSON(); got != `{"confirm":true,"draft_id":312,"tool_id":8} {"confirm":true,"draft_id":313,"tool_id":8}` {
		t.Errorf("sent %s", got)
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
	if want := []string{"mail_update"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].JSON(); got != `{"bcc":"boss@example.com","body":"<p>Hi</p><p>Bye</p>","cc":"","draft_id":312,"html":true,"subject":"Plans, again","tool_id":8}` {
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

	if want := []string{"mail_draft", "mail_reply", "mail_forward"}; !slices.Equal(fake.requests, want) {
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
	if want := []string{"mail_reply"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
}

func TestSendingWithAttachmentsGoesThroughADraftThatHasThem(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, &mailFake{fake, map[string]string{"mail_send": "Re: Plans"}}, &opened)
	offer := filepath.Join(t.TempDir(), "offer.pdf")
	if err := os.WriteFile(offer, []byte("pdf"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := invoke(ctx, "mail reply", "8/310", "--body", "Sure", "--send", "--attach", offer); err != nil {
		t.Fatal(err)
	}

	// The reply is saved, the file attached to that draft, and the draft sent with what it has
	if want := []string{"mail_reply", "mail_send"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if want := []string{"/tools/8/mails/drafts/400/attachments: files[]=offer.pdf"}; !slices.Equal(fake.uploads, want) {
		t.Errorf("uploads %v", fake.uploads)
	}
	if got := sent[1].JSON(); got != `{"confirm":true,"draft_id":400,"tool_id":8}` {
		t.Errorf("send %s", got)
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
	fake.errors = map[string]error{"mail_move": &api.Error{Message: "Invalid folder name (HTTP 422)", Status: 422}}
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

	if want := []string{"mail_trash", "mail_trash", "mail_restore", "mail_discard"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].JSON() + " " + sent[3].JSON(); got != `{"mail_id":310,"tool_id":8} {"draft_id":312,"tool_id":8}` {
		t.Errorf("sent %s", got)
	}
	if got := sent[1].Get("folder").S(); got != "Receipts" {
		t.Errorf("folder %q", got)
	}
	if !strings.Contains(out.String(), "Discarded draft 8/400") || !strings.Contains(out.String(), "dobase mail restore 8/400") {
		t.Errorf("out %q", out.String())
	}
}

func TestJunkIsItsOwnCommand(t *testing.T) {
	var sent []api.Value
	var opened []string
	var out bytes.Buffer
	fake := newFakeAPI(mailWithAttachments, &sent)
	ctx := mailCtx(&out, false, fake, &opened)

	if err := invoke(ctx, "mail move", "8/310", "junk"); api.KindOf(err) != api.Usage || !strings.Contains(err.Error(), "dobase mail junk") {
		t.Errorf("got %v", err)
	}
	for _, command := range [][]string{{"mail junk", "8/310", "--folder", "Receipts"}, {"mail not-junk", "8/310"}} {
		if err := invoke(ctx, command[0], command[1:]...); err != nil {
			t.Fatal(err)
		}
	}

	if want := []string{"mail_junk", "mail_not_junk"}; !slices.Equal(fake.requests, want) {
		t.Errorf("requests %v", fake.requests)
	}
	if got := sent[0].Get("folder").S(); got != "Receipts" {
		t.Errorf("folder %q", got)
	}
	if !strings.Contains(out.String(), "dobase mail not-junk 8/") || !strings.Contains(out.String(), "to the inbox.") {
		t.Errorf("out %q", out.String())
	}
}
