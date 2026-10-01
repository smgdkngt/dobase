package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// themeAPI is the appearance endpoint: it remembers what was sent and answers
// the way the server does.
type themeAPI struct {
	fakeAPI
	current api.Value
}

func (f *themeAPI) Request(method api.Method, path string, _ []api.Param, body any) (api.Value, error) {
	if path != "/appearance" {
		panic("unexpected path " + path)
	}
	if method == api.Patch {
		sent := api.Of(body)
		*f.sent = append(*f.sent, sent)
		if sent.Has("typeface") {
			f.current = f.current.With("typeface", sent.Get("typeface"))
			return f.current, nil
		}
		name := sent.Get("theme")
		switch {
		case name.IsNull():
			f.current = api.Object("name", nil, "custom", false)
		case sent.Has("colors"):
			f.current = api.Object("name", name, "label", "Mine", "mode", sent.Get("colors", "mode").Or("dark"), "custom", true)
		case name.S() == "nord":
			f.current = api.Object("name", "nord", "label", "Nord", "mode", "dark", "custom", false)
		default:
			return api.Null, api.Failf("Unknown theme. Pick one of the built-in themes, or send its colors.")
		}
	}
	return f.current.With("themes", []any{
		map[string]any{"name": "catppuccin-latte", "label": "Catppuccin Latte", "mode": "light"},
		map[string]any{"name": "nord", "label": "Nord", "mode": "dark"},
	}), nil
}

func themeCtx(t *testing.T) (*command.Ctx, *bytes.Buffer, *[]api.Value) {
	t.Helper()
	var out bytes.Buffer
	sent := &[]api.Value{}
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(&themeAPI{fakeAPI: fakeAPI{sent: sent}, current: api.Object("name", nil, "custom", false)})
	return ctx, &out, sent
}

func TestThemeSetAndList(t *testing.T) {
	ctx, out, sent := themeCtx(t)

	if err := invoke(ctx, "theme set", "Nord"); err != nil {
		t.Fatal(err)
	}
	if got := (*sent)[0].JSON(); got != `{"theme":"nord"}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), "Dobase now wears Nord (dark).") {
		t.Errorf("out %q", out.String())
	}

	out.Reset()
	if err := invoke(ctx, "theme list"); err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 3 || !strings.Contains(lines[0], "default") || strings.HasPrefix(lines[0], "*") ||
		!strings.HasPrefix(lines[2], "*") || !strings.Contains(lines[2], "nord") {
		t.Errorf("list %q", out.String())
	}

	out.Reset()
	if err := invoke(ctx, "theme set", "default"); err != nil {
		t.Fatal(err)
	}
	if got := (*sent)[1].JSON(); got != `{"theme":null}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), "back in its own look") {
		t.Errorf("out %q", out.String())
	}

	if err := invoke(ctx, "theme set", "no-such"); err == nil || !strings.Contains(err.Error(), "Unknown theme") {
		t.Errorf("got %v", err)
	}
}

func TestThemeFontSetsTheTypeface(t *testing.T) {
	ctx, out, sent := themeCtx(t)

	if err := invoke(ctx, "theme font", "Mono"); err != nil {
		t.Fatal(err)
	}
	if got := (*sent)[0].JSON(); got != `{"typeface":"mono"}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), "set in your monospace font") {
		t.Errorf("out %q", out.String())
	}

	out.Reset()
	if err := invoke(ctx, "theme font", "default"); err != nil {
		t.Fatal(err)
	}
	if got := (*sent)[1].JSON(); got != `{"typeface":null}` {
		t.Errorf("sent %s", got)
	}
	if !strings.Contains(out.String(), "back in its own typeface") {
		t.Errorf("out %q", out.String())
	}

	if err := invoke(ctx, "theme font", "comic sans"); err == nil || !strings.Contains(err.Error(), "mono or default") {
		t.Errorf("got %v", err)
	}
	if len(*sent) != 2 {
		t.Errorf("sent %d requests", len(*sent))
	}
}

// omarchy lays out a home directory the way Omarchy keeps its current theme.
func omarchy(t *testing.T, name, colors string) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	current := filepath.Join(home, ".local", "state", "omarchy", "current")
	if err := os.MkdirAll(filepath.Join(current, "theme"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, ".config", "omarchy"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(current, "theme.name"), []byte(name+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if colors != "" {
		if err := os.WriteFile(filepath.Join(current, "theme", "colors.toml"), []byte(colors), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return home
}

func TestThemeSyncSendsTheDesktopsPalette(t *testing.T) {
	omarchy(t, "tokyo-night", `mode = "dark"

accent = "#7AA2F7"   # blue
selection = "#292e42"
background = "#1a1b26"
dark_background = "#13141c"
foreground = '#a9b1d6'
red = "#f7768e"
gradient = "#7aa2f7 #bb9af7 45deg"
`)
	ctx, out, sent := themeCtx(t)

	if err := invoke(ctx, "theme sync"); err != nil {
		t.Fatal(err)
	}
	body := (*sent)[0]
	if body.Get("theme").S() != "tokyo-night" {
		t.Errorf("theme %s", body.JSON())
	}
	want := `{"accent":"#7aa2f7","background":"#1a1b26","dark_background":"#13141c","foreground":"#a9b1d6","mode":"dark","red":"#f7768e"}`
	if got := api.Of(body.Get("colors")).JSON(); !sameJSON(got, want) {
		t.Errorf("colors %s", got)
	}
	if !strings.Contains(out.String(), "Dobase now wears Mine (dark, your own colours).") {
		t.Errorf("out %q", out.String())
	}
}

func TestThemeSyncReadsOlderPalettesAndFallsBackToTheName(t *testing.T) {
	home := omarchy(t, "My Theme", "bg = \"#101010\"\nfg = \"#EEEEEE\"\ncolor4 = \"#3366ff\"\ncolor1 = \"#ff0000\"\n")
	ctx, _, sent := themeCtx(t)

	if err := invoke(ctx, "theme sync"); err != nil {
		t.Fatal(err)
	}
	body := (*sent)[0]
	if body.Get("theme").S() != "my-theme" || body.Get("colors", "accent").S() != "#3366ff" ||
		body.Get("colors", "blue").S() != "#3366ff" || body.Get("colors", "background").S() != "#101010" {
		t.Errorf("sent %s", body.JSON())
	}

	// No colors.toml (an older Omarchy theme): the name alone, for a built-in theme
	if err := os.Remove(filepath.Join(home, ".local", "state", "omarchy", "current", "theme", "colors.toml")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".local", "state", "omarchy", "current", "theme.name"), []byte("nord"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "theme sync"); err != nil {
		t.Fatal(err)
	}
	if got := (*sent)[1].JSON(); got != `{"theme":"nord"}` {
		t.Errorf("sent %s", got)
	}
}

func TestThemeSyncNeedsATheme(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	ctx, _, sent := themeCtx(t)

	if err := invoke(ctx, "theme sync"); err == nil || !strings.Contains(err.Error(), "No Omarchy theme found") {
		t.Errorf("got %v", err)
	}

	broken := filepath.Join(t.TempDir(), "colors.toml")
	if err := os.WriteFile(broken, []byte("background = \"#101010\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := invoke(ctx, "theme sync", "--file", broken, "--name", "x"); err == nil || !strings.Contains(err.Error(), "no foreground colour") {
		t.Errorf("got %v", err)
	}
	if len(*sent) != 0 {
		t.Errorf("sent %d requests", len(*sent))
	}
}

func TestThemeFollowWritesTheHookAndStopRemovesIt(t *testing.T) {
	home := omarchy(t, "nord", "background = \"#2e3440\"\nforeground = \"#d8dee9\"\naccent = \"#81a1c1\"\n")
	ctx, out, sent := themeCtx(t)
	hook := filepath.Join(home, ".config", "omarchy", "hooks", "theme-set.d", "dobase")

	if err := invoke(ctx, "theme follow"); err != nil {
		t.Fatal(err)
	}
	script, err := os.ReadFile(hook)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(script), "#!/bin/bash\n") || !strings.Contains(string(script), " theme sync >/dev/null 2>&1 &\n") {
		t.Errorf("hook %q", script)
	}
	if info, _ := os.Stat(hook); info.Mode().Perm()&0o100 == 0 {
		t.Errorf("hook isn't executable: %v", info.Mode())
	}
	if len(*sent) != 1 || !strings.Contains(out.String(), "follows your Omarchy theme") {
		t.Errorf("sent %d, out %q", len(*sent), out.String())
	}

	if err := invoke(ctx, "theme follow", "--stop"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(hook); !os.IsNotExist(err) {
		t.Errorf("hook still there: %v", err)
	}
	// Stopping twice is fine
	if err := invoke(ctx, "theme follow", "--stop"); err != nil {
		t.Fatal(err)
	}
}

func TestThemeFollowNeedsOmarchy(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	ctx, _, _ := themeCtx(t)

	if err := invoke(ctx, "theme follow"); err == nil || !strings.Contains(err.Error(), "doesn't look like an Omarchy desktop") {
		t.Errorf("got %v", err)
	}
}

func sameJSON(got, want string) bool {
	return api.MustParse(got).Equal(api.MustParse(want)) || sortedJSON(got) == sortedJSON(want)
}

// sortedJSON orders the pairs of a flat object, since a Go map has no order.
func sortedJSON(text string) string {
	value := api.MustParse(text)
	keys := value.Keys()
	pairs := make([]string, 0, len(keys))
	for _, key := range keys {
		pairs = append(pairs, key+"="+value.Get(key).S())
	}
	for i := range pairs {
		for j := i + 1; j < len(pairs); j++ {
			if pairs[j] < pairs[i] {
				pairs[i], pairs[j] = pairs[j], pairs[i]
			}
		}
	}
	return strings.Join(pairs, ",")
}
