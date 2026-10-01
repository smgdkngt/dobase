// Tests that need no server: the commands and their help, argument parsing,
// the input helpers commands rely on, and commands against a fake API.
package cli

import (
	"bytes"
	"fmt"
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/commands"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

func run(args ...string) (int, string, string) {
	var out, errOut bytes.Buffer
	status := Run(args, &out, &errOut)
	return status, out.String(), errOut.String()
}

func TestHelpListsEveryCommand(t *testing.T) {
	status, out, _ := run("help")
	if status != 0 {
		t.Fatalf("status %d", status)
	}
	for _, definition := range commands.Definitions() {
		if !strings.Contains(out, "dobase "+definition.Name) {
			t.Errorf("help misses %s", definition.Name)
		}
	}
}

func TestNounHelpShowsFlags(t *testing.T) {
	status, out, _ := run("help", "chat")
	if status != 0 || !strings.Contains(out, "--reply-to ID") {
		t.Fatalf("status %d, out %q", status, out)
	}
}

func TestCommandHelpShowsUsage(t *testing.T) {
	status, out, _ := run("chat", "post", "--help")
	if status != 0 || !strings.HasPrefix(out, "Usage: dobase chat post TOOL TEXT") {
		t.Fatalf("status %d, out %q", status, out)
	}
}

func TestUnknownCommandsExitWithAUsageError(t *testing.T) {
	status, _, err := run("frobnicate")
	if status != 2 || !strings.Contains(err, "Unknown command") {
		t.Fatalf("status %d, err %q", status, err)
	}
}

func TestWrongArgumentsExitWithAUsageError(t *testing.T) {
	for _, c := range []struct {
		args   []string
		prefix string
	}{
		{[]string{"chat", "post", "team"}, "Usage: dobase chat post TOOL TEXT"},
		{[]string{"chat", "post", "team", "hi", "--bogus"}, "invalid option: --bogus"},
		{[]string{"chat", "post", "team", "hi", "--reply-to"}, "missing argument: --reply-to"},
		{[]string{"chat", "post", "team", "hi", "--html=yes"}, "needless argument: --html=yes"},
	} {
		status, _, err := run(c.args...)
		if status != 2 || !strings.HasPrefix(err, c.prefix) {
			t.Errorf("%v: status %d, err %q", c.args, status, err)
		}
	}
}

func TestEveryCommandHasASummaryAndWellFormedArguments(t *testing.T) {
	nouns := map[string]bool{}
	for _, noun := range commands.Nouns() {
		nouns[noun.Name] = true
	}
	wellFormed := regexp.MustCompile(`^[A-Z/]+$`)
	for _, definition := range commands.Definitions() {
		if definition.Summary == "" {
			t.Errorf("%s has no summary", definition.Name)
		}
		for _, arg := range definition.Args {
			bare := strings.TrimSuffix(strings.TrimSuffix(strings.TrimPrefix(arg, "["), "]"), "...")
			if !wellFormed.MatchString(bare) {
				t.Errorf("%s has odd args: %s", definition.Name, arg)
			}
		}
		if noun := definition.Noun(); noun != "" && !nouns[noun] {
			t.Errorf("%s has no noun summary", definition.Name)
		}
	}
}

func TestTheSkillAndReadmesOnlyShowCommandsAndFlagsThatExist(t *testing.T) {
	definitions := commands.Definitions()
	examples := 0
	for _, file := range []string{"../../SKILL.md", "../../README.md", "../../../README.md"} {
		contents, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, line := range strings.Split(string(contents), "\n") {
			line, ok := strings.CutPrefix(line, "dobase ")
			if !ok {
				continue
			}
			line, _, _ = strings.Cut(line, " #")
			line, _, _ = strings.Cut(strings.TrimRight(line, " "), " <<'")
			words := shellWords(line)
			if len(words) == 0 || words[0] == "help" || strings.HasPrefix(words[0], "-") {
				continue
			}
			examples++

			var definition *command.Definition
			for _, d := range definitions {
				if len(words) > 1 && d.Name == words[0]+" "+words[1] {
					definition = d
				}
			}
			for _, d := range definitions {
				if definition == nil && d.Name == words[0] {
					definition = d
				}
			}
			if definition == nil {
				t.Errorf("%s: unknown command in `%s`", file, line)
				continue
			}
			for _, word := range words {
				flag, ok := strings.CutPrefix(word, "--")
				if !ok || flag == "" {
					continue
				}
				flag, _, _ = strings.Cut(flag, "=")
				known := flag == "json"
				for _, f := range definition.Flags {
					known = known || f.Name == flag
				}
				if !known {
					t.Errorf("%s: `%s` has no --%s (in `%s`)", file, definition.Name, flag, line)
				}
			}
		}
	}
	if examples <= 20 {
		t.Errorf("only %d examples found", examples)
	}
}

func TestPrintedTextLosesControlCharactersButKeepsNewlinesAndTabs(t *testing.T) {
	got := command.Clean("Hi \x1b]52;c;cHduZWQ=\x07\x1b[2Jthere\n\ttabbed\u009b")
	if want := "Hi ]52;c;cHduZWQ=[2Jthere\n\ttabbed"; got != want {
		t.Fatalf("got %q", got)
	}
}

func TestPlainTextBecomesEscapedParagraphs(t *testing.T) {
	got := command.Paragraphs("Hello <b>you</b>\nsecond line\n\n\nNew paragraph\n")
	if want := "<p>Hello &lt;b&gt;you&lt;/b&gt;<br>second line</p><p>New paragraph</p>"; got != want {
		t.Fatalf("got %q", got)
	}
	if got := command.Paragraphs("One\r\n  \r\nTwo  \n\t\nThree"); got != "<p>One</p><p>Two</p><p>Three</p>" {
		t.Fatalf("got %q", got)
	}
}

func TestPlainTextLinksURLs(t *testing.T) {
	for text, want := range map[string]string{
		"see https://example.com":                                                     `<p>see <a href="https://example.com">https://example.com</a></p>`,
		"Done: https://example.com/a?x=1&y=<2>.":                                      `<p>Done: <a href="https://example.com/a?x=1&amp;y=">https://example.com/a?x=1&amp;y=</a>&lt;2&gt;.</p>`,
		"(https://example.com/wiki/Go_(game)), then":                                  `<p>(<a href="https://example.com/wiki/Go_(game)">https://example.com/wiki/Go_(game)</a>), then</p>`,
		"HTTP://Example.com/x; and http://a.b:8080/c":                                 `<p><a href="HTTP://Example.com/x">HTTP://Example.com/x</a>; and <a href="http://a.b:8080/c">http://a.b:8080/c</a></p>`,
		"say \"https://example.com/it's\"!\nnext":                                     `<p>say &quot;<a href="https://example.com/it&#39;s">https://example.com/it&#39;s</a>&quot;!<br>next</p>`,
		"not a link: ftp://example.com, https://, xhttps://example.com and https://.": `<p>not a link: ftp://example.com, https://, xhttps://example.com and https://.</p>`,
	} {
		if got := command.Paragraphs(text); got != want {
			t.Errorf("%q:\ngot  %s\nwant %s", text, got, want)
		}
	}
}

func TestDatesAcceptKeywordsAndISODatesOnly(t *testing.T) {
	for value, want := range map[string]string{"none": "", "today": command.Today().Format(command.DateLayout), "2026-10-01": "2026-10-01"} {
		if got, err := command.DateParam(value); err != nil || got != want {
			t.Errorf("%s: got %q, %v", value, got, err)
		}
	}
	for _, value := range []string{"friday", "2026-02-30", "2026-1-01"} {
		if _, err := command.DateParam(value); api.KindOf(err) != api.Usage {
			t.Errorf("%s: %v", value, err)
		}
	}
}

func TestToolAndIDReferencesMustEndInANumericID(t *testing.T) {
	ctx := command.NewCtx(&config.Config{}, &bytes.Buffer{}, false, "test")
	for _, reference := range []string{"104", "roadmap/abc", "/104"} {
		if _, _, err := ctx.ToolAndID(reference, "boards", "card"); api.KindOf(err) != api.Usage {
			t.Errorf("%s: %v", reference, err)
		}
	}
}

func TestJSONKeepsTheServersKeyOrderAndDoesNotEscapeHTML(t *testing.T) {
	value := api.MustParse(`{"z": 1, "a": [true, null, 1.50], "html": "<p>&</p>", "empty": {}, "none": []}`)
	want := "{\n  \"z\": 1,\n  \"a\": [\n    true,\n    null,\n    1.50\n  ],\n  \"html\": \"<p>&</p>\",\n  \"empty\": {},\n  \"none\": []\n}"
	if got := value.Pretty(); got != want {
		t.Fatalf("got %s", got)
	}
}

// fakeAPI answers GETs from a fixed set of paths, records every other request's
// body and the paths it sent to or downloaded from, and saves downloads as
// "data from PATH".
type fakeAPI struct {
	responses api.Value
	sent      *[]api.Value
	paths     []string
}

func newFakeAPI(responses string, sent *[]api.Value) *fakeAPI {
	return &fakeAPI{responses: api.MustParse(responses), sent: sent}
}

func (f *fakeAPI) Request(method api.Method, path string, _ []api.Param, body any) (api.Value, error) {
	if method == api.Get {
		return f.responses.Get(path), nil
	}
	sent := api.Of(body)
	*f.sent = append(*f.sent, sent)
	f.paths = append(f.paths, path)
	return api.Object("id", 400, "subject", sent.Get("subject"), "to", []string{"ann@example.com"}, "cc", []string{},
		"url", "https://dobase.test/tools/8/mails/new?draft_id=400"), nil
}

func (f *fakeAPI) Upload(string, []api.FilePart, []api.Param) (api.Value, error) {
	panic("unexpected upload")
}

func (f *fakeAPI) Download(path, destination string) (string, error) {
	f.paths = append(f.paths, path)
	if err := os.WriteFile(destination, []byte("data from "+path), 0o644); err != nil {
		panic(err)
	}
	return "", nil
}

// invoke runs one command in ctx.
func invoke(ctx *command.Ctx, name string, argv ...string) error {
	for _, definition := range commands.Definitions() {
		if definition.Name == name {
			args, err := definition.Parse(argv)
			if err != nil {
				return err
			}
			return definition.Run(ctx, args)
		}
	}
	panic(fmt.Sprintf("no command %s", name))
}

func TestChatPostsParagraphsAndRepliesToTheMessageGiven(t *testing.T) {
	var sent []api.Value
	var out bytes.Buffer
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(newFakeAPI(`{"/tools": [{"id": 12, "name": "Team", "type": "chat"}, {"id": 13, "name": "Team board", "type": "boards"}]}`, &sent))

	if err := invoke(ctx, "chat post", "team", "Hi <you>\n\nBye", "--reply-to", "12/77"); err != nil {
		t.Fatal(err)
	}
	if got := sent[0].JSON(); got != `{"message":{"body":"<p>Hi &lt;you&gt;</p><p>Bye</p>","reply_to_id":"77"}}` {
		t.Errorf("sent %s", got)
	}
	if err := invoke(ctx, "chat post", "team", "see https://example.com", "--html"); err != nil {
		t.Fatal(err)
	}
	if got := sent[1].JSON(); got != `{"message":{"body":"see https://example.com"}}` {
		t.Errorf("sent %s", got)
	}
	if err := invoke(ctx, "chat post", "board", "Hi"); err == nil || !strings.Contains(err.Error(), "Team board (13) is a boards tool, not chat.") {
		t.Errorf("got %v", err)
	}
	if !strings.Contains(out.String(), "Posted message 12/400 to Team.") {
		t.Errorf("out %q", out.String())
	}
}

// shellWords splits a command line like a shell: spaces separate words, quotes group them.
func shellWords(line string) []string {
	var words []string
	var word strings.Builder
	var quote rune
	started := false
	for _, char := range line {
		switch {
		case quote == 0 && (char == '"' || char == '\''):
			quote, started = char, true
		case quote != 0 && char == quote:
			quote = 0
		case quote == 0 && char == ' ':
			if started {
				words = append(words, word.String())
				word.Reset()
				started = false
			}
		default:
			word.WriteRune(char)
			started = true
		}
	}
	if started {
		words = append(words, word.String())
	}
	return words
}

func TestTextThatStartsWithADashIsTextNotAnOption(t *testing.T) {
	var sent []api.Value
	ctx, _ := newBoardsCtx(&sent)

	texts := []string{"- first point", "-5 degrees", "-x", "--- cut here ---", "-- Sem", "--force didn't help", "-"}
	ctx.Stdin = strings.NewReader("from stdin")
	for _, text := range texts {
		if err := invoke(ctx, "card comment", "13/104", text); err != nil {
			t.Fatalf("%q: %v", text, err)
		}
	}
	for i, want := range []string{"- first point", "-5 degrees", "-x", "--- cut here ---", "-- Sem", "--force didn&#39;t help", "from stdin"} {
		if got := sent[i].Get("body").S(); got != "<p>"+want+"</p>" {
			t.Errorf("%q was sent as %q", texts[i], got)
		}
	}

	// A flag's value may start with a dash too, and flags still work around the text
	if err := invoke(ctx, "card create", "roadmap", "-1 day", "--description", "- one\n- two", "--column=Doing"); err != nil {
		t.Fatal(err)
	}
	if got := sent[len(sent)-1].JSON(); got != `{"card":{"description":"<p>- one<br>- two</p>","title":"-1 day"}}` {
		t.Errorf("sent %s", got)
	}

	// What looks like an option the command doesn't have is still a mistake, unless it comes after --
	for _, option := range []string{"--bogus", "--bogus=1", "--no-verify"} {
		if err := invoke(ctx, "card comment", "13/104", option); api.KindOf(err) != api.Usage || !strings.HasPrefix(err.Error(), "invalid option: "+option) {
			t.Errorf("%s: %v", option, err)
		}
	}
	if err := invoke(ctx, "card comment", "13/104", "--", "--html"); err != nil {
		t.Fatal(err)
	}
	if got := sent[len(sent)-1].Get("body").S(); got != "<p>--html</p>" {
		t.Errorf("after --, --html was sent as %q", got)
	}
}

func TestJSONIsOnlyAnOptionBeforeTheDoubleDash(t *testing.T) {
	for _, c := range []struct {
		argv []string
		rest []string
		json bool
	}{
		{[]string{"tool", "list", "--json"}, []string{"tool", "list"}, true},
		{[]string{"--json", "chat", "post", "team", "--", "hi"}, []string{"chat", "post", "team", "--", "hi"}, true},
		{[]string{"chat", "post", "team", "--", "--json"}, []string{"chat", "post", "team", "--", "--json"}, false},
		{[]string{"chat", "post", "--json", "team", "--", "--json", "--"}, []string{"chat", "post", "team", "--", "--json", "--"}, true},
	} {
		rest, json := withoutJSON(c.argv)
		if !slices.Equal(rest, c.rest) || json != c.json {
			t.Errorf("%v: got %v, %v", c.argv, rest, json)
		}
	}

	// Nothing is signed in here, so the command stops before it reaches a server
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("DOBASE_URL", "")
	t.Setenv("DOBASE_TOKEN", "")
	status, _, err := run("chat", "post", "team", "--", "--json")
	if status != 1 || !strings.Contains(err, "Not signed in") {
		t.Errorf("status %d, err %q", status, err)
	}
}
