package commands

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func theme() []*Definition {
	return []*Definition{
		New("theme list", "List the themes Dobase comes with (* = yours)", nil, nil, listThemes),
		New("theme set", "Wear a built-in theme; `default` is Dobase's own light and dark", []string{"NAME"}, nil, setTheme),
		New("theme sync", "Wear the theme your Omarchy desktop is on, colours and all", nil,
			[]Flag{F("file", "PATH", "A colors.toml to read instead of the desktop's current theme"),
				F("name", "NAME", "What to call it (default: the desktop theme's name)")}, syncTheme),
		New("theme follow", "Change along with Omarchy: its theme-set hook runs `dobase theme sync`", nil,
			[]Flag{Switch("stop", "Remove the hook again")}, followTheme),
	}
}

func listThemes(ctx *Ctx, _ *Args) error {
	appearance, err := ctx.Get("/appearance")
	if err != nil {
		return err
	}
	return ctx.Output(appearance, func() error {
		current := appearance.Get("name").S()
		custom := appearance.Get("custom").Truthy()

		rows := [][]string{{If(current == "", "*"), "default", "Dobase", "light and dark, with your system"}}
		if custom {
			rows = append(rows, []string{"*", current, appearance.Get("label").S(), appearance.Get("mode").S() + ", your own colours"})
		}
		for _, theme := range appearance.Get("themes").Items() {
			name := theme.Get("name").S()
			rows = append(rows, []string{If(!custom && name == current, "*"), name, theme.Get("label").S(), theme.Get("mode").S()})
		}
		ctx.Table(rows, 0)
		return nil
	})
}

func setTheme(ctx *Ctx, args *Args) error {
	name := strings.ToLower(strings.TrimSpace(args.At(0)))
	body := map[string]any{"theme": name}
	if name == "default" || name == "dobase" {
		body["theme"] = nil
	}
	appearance, err := ctx.Patch("/appearance", body)
	if err != nil {
		return err
	}
	return ctx.Output(appearance, func() error {
		ctx.Say(wearing(appearance))
		return nil
	})
}

func syncTheme(ctx *Ctx, args *Args) error {
	file, name := args.Value("file"), args.Value("name")
	if file == "" {
		directory, found := omarchyThemeDirectory()
		if !found {
			return api.Failf("No Omarchy theme found under ~/.local/state/omarchy or ~/.config/omarchy. Give a colors.toml with --file.")
		}
		file = filepath.Join(directory, "colors.toml")
		if name == "" {
			name = omarchyThemeName(directory)
		}
	}
	if name == "" {
		name = strings.TrimSuffix(filepath.Base(filepath.Dir(file)), string(filepath.Separator))
	}
	name = slug(name)

	body := map[string]any{"theme": name}
	colors, err := readPalette(file)
	switch {
	case err == nil:
		body["colors"] = colors
	case args.Value("file") != "":
		return err
	}
	// An older Omarchy theme has no colors.toml; its name still finds a built-in one

	appearance, err := ctx.Patch("/appearance", body)
	if err != nil {
		return err
	}
	return ctx.Output(appearance, func() error {
		ctx.Say(wearing(appearance))
		return nil
	})
}

func followTheme(ctx *Ctx, args *Args) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return api.Failf("Could not find your home directory: %v", err)
	}
	hooks := filepath.Join(home, ".config", "omarchy", "hooks")
	hook := filepath.Join(hooks, "theme-set.d", "dobase")

	if args.On("stop") {
		if err := os.Remove(hook); err != nil && !os.IsNotExist(err) {
			return api.Failf("Could not remove %s: %v", hook, err)
		}
		ctx.Say("Dobase no longer follows your Omarchy theme. The theme it has now stays.")
		return nil
	}

	if _, err := os.Stat(filepath.Join(home, ".config", "omarchy")); err != nil {
		return api.Failf("No ~/.config/omarchy here, so this doesn't look like an Omarchy desktop.")
	}
	binary, err := os.Executable()
	if err != nil {
		binary = "dobase"
	}
	script := "#!/bin/bash\n" +
		"# Keeps Dobase on the theme of this desktop. Written by `dobase theme follow`;\n" +
		"# `dobase theme follow --stop` removes it.\n" +
		fmt.Sprintf("%q theme sync >/dev/null 2>&1 &\n", binary)
	if err := os.MkdirAll(filepath.Dir(hook), 0o755); err != nil {
		return api.Failf("Could not create %s: %v", filepath.Dir(hook), err)
	}
	if err := os.WriteFile(hook, []byte(script), 0o755); err != nil {
		return api.Failf("Could not write %s: %v", hook, err)
	}

	ctx.Sayf("Dobase follows your Omarchy theme from now on (%s).", hook)
	return syncTheme(ctx, &Args{})
}

func wearing(appearance api.Value) string {
	if appearance.Get("name").IsNull() {
		return "Dobase is back in its own look, light or dark with your system."
	}
	return fmt.Sprintf("Dobase now wears %s (%s%s).", appearance.Get("label").S(), appearance.Get("mode").S(),
		If(appearance.Get("custom").Truthy(), ", your own colours"))
}

// -- Omarchy ---------------------------------------------------------------------

// omarchyThemeDirectory is where the current theme lives: Omarchy keeps a link to
// it in its state directory, and kept it in its config directory before that.
func omarchyThemeDirectory() (string, bool) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", false
	}
	for _, directory := range []string{
		filepath.Join(home, ".local", "state", "omarchy", "current", "theme"),
		filepath.Join(home, ".config", "omarchy", "current", "theme"),
	} {
		if info, err := os.Stat(directory); err == nil && info.IsDir() {
			return directory, true
		}
	}
	return "", false
}

// omarchyThemeName reads theme.name next to the link, or the name of the
// directory the link points at.
func omarchyThemeName(directory string) string {
	if name, err := os.ReadFile(directory + ".name"); err == nil && strings.TrimSpace(string(name)) != "" {
		return strings.TrimSpace(string(name))
	}
	if target, err := filepath.EvalSymlinks(directory); err == nil {
		return filepath.Base(target)
	}
	return filepath.Base(directory)
}

var (
	hexColor      = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
	paletteColors = []string{"background", "dark_background", "foreground", "bright_foreground", "accent",
		"red", "yellow", "orange", "green", "cyan", "blue", "magenta"}
	// Names older themes use for the same colours
	paletteAliases = map[string]string{
		"bg": "background", "dark_bg": "dark_background", "fg": "foreground", "bright_fg": "bright_foreground",
		"color0": "background", "color7": "foreground", "color15": "bright_foreground",
		"color1": "red", "color2": "green", "color3": "yellow", "color4": "blue", "color5": "magenta", "color6": "cyan",
		"purple": "magenta",
	}
)

// readPalette takes the colours Dobase themes with from an Omarchy colors.toml.
func readPalette(path string) (map[string]any, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, api.Failf("Could not read %s: %v", path, err)
	}
	defer file.Close()

	values := map[string]string{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, found := strings.Cut(scanner.Text(), "=")
		key = strings.Trim(strings.TrimSpace(key), `"'`)
		if !found || key == "" || strings.HasPrefix(key, "#") {
			continue
		}
		value = strings.TrimSpace(value)
		if quote := strings.IndexAny(value, `"'`); quote >= 0 {
			value = value[quote+1:]
			if end := strings.IndexAny(value, `"'`); end >= 0 {
				value = value[:end]
			}
		}
		values[key] = strings.TrimSpace(value)
	}

	for alias, name := range paletteAliases {
		if values[name] == "" {
			values[name] = values[alias]
		}
	}
	if values["accent"] == "" {
		values["accent"] = values["blue"]
	}

	colors := map[string]any{}
	for _, name := range paletteColors {
		if hexColor.MatchString(values[name]) {
			colors[name] = strings.ToLower(values[name])
		}
	}
	for _, name := range []string{"background", "foreground", "accent"} {
		if colors[name] == nil {
			return nil, api.Failf("%s has no %s colour, so it can't make a theme.", path, name)
		}
	}
	if mode := values["mode"]; mode == "light" || mode == "dark" {
		colors["mode"] = mode
	} else if mode := values["theme_type"]; mode == "light" || mode == "dark" {
		colors["mode"] = mode
	}
	return colors, nil
}

var notSlug = regexp.MustCompile(`[^a-z0-9]+`)

func slug(name string) string {
	return strings.Trim(notSlug.ReplaceAllString(strings.ToLower(name), "-"), "-")
}
