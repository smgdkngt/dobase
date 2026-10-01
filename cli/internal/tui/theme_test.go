package tui

import (
	"testing"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

func TestTheAppWearsThePersonsTheme(t *testing.T) {
	t.Cleanup(func() { wearing = ownPalette })

	wearTheme(api.MustParse(`{"name": "gruvbox", "colors": {"background": "#282828", "foreground": "#d4be98",
		"accent": "#7daea3", "red": "#ea6962", "yellow": "#d8a657", "green": "#a9b665", "magenta": "#d3869b"}}`))

	if wearing.accent != (tone{0x7d, 0xae, 0xa3}) || wearing.danger != (tone{0xea, 0x69, 0x62}) {
		t.Errorf("accent %v, danger %v", wearing.accent, wearing.danger)
	}
	// A pastel accent is written on in the theme's dark background, not in white
	if wearing.onAccent != (tone{0x28, 0x28, 0x28}) {
		t.Errorf("on the accent: %v", wearing.onAccent)
	}
	if wearing.cards["purple"] != (tone{0xd3, 0x86, 0x9b}) || wearing.cards["orange"] != (tone{0xd8, 0xa6, 0x57}) {
		t.Errorf("cards %v", wearing.cards)
	}
	if wearing.logoFrom != wearing.accent || wearing.logoTo != (tone{0xd3, 0x86, 0x9b}) {
		t.Errorf("logo %v to %v", wearing.logoFrom, wearing.logoTo)
	}
	if wearing.muted == ownPalette.muted {
		t.Errorf("muted stayed %v", wearing.muted)
	}

	// A dark accent keeps white on it
	wearTheme(api.MustParse(`{"colors": {"background": "#fafafa", "foreground": "#212121", "accent": "#3264eb"}}`))
	if wearing.onAccent != (tone{255, 255, 255}) || wearing.success != ownPalette.success {
		t.Errorf("on the accent: %v, success %v", wearing.onAccent, wearing.success)
	}
}

func TestWithoutAThemeTheAppKeepsItsOwnColors(t *testing.T) {
	t.Cleanup(func() { wearing = ownPalette })
	wearTheme(api.MustParse(`{"colors": {"background": "#282828", "foreground": "#d4be98", "accent": "#7daea3"}}`))

	for _, answer := range []string{`{"name": null, "colors": null}`, `{}`, `null`, `{"colors": {"accent": "teal"}}`} {
		wearTheme(api.MustParse(`{"colors": {"background": "#282828", "foreground": "#d4be98", "accent": "#7daea3"}}`))
		wearTheme(api.MustParse(answer))
		if wearing.accent != ownPalette.accent {
			t.Errorf("after %s the accent is %v", answer, wearing.accent)
		}
	}
}

// themeServer answers the appearance request and nothing else.
type themeServer struct{ fakeServer }

func (s *themeServer) Request(method api.Method, path string, params []api.Param, body any) (api.Value, error) {
	if path == "/appearance" {
		return api.MustParse(`{"colors": {"background": "#1a1b26", "foreground": "#a9b1d6", "accent": "#7aa2f7"}}`), nil
	}
	return api.Null, nil
}

func TestTheThemeIsAskedForInTheBackground(t *testing.T) {
	t.Cleanup(func() { wearing = ownPalette })
	app := NewApp(&themeServer{}, "https://dobase.test", nil)
	app.refreshInBackground(&themeServer{})

	deadline := time.Now().Add(2 * time.Second)
	for wearing.accent == ownPalette.accent && time.Now().Before(deadline) {
		app.pollBackground()
		time.Sleep(5 * time.Millisecond)
	}
	if wearing.accent != (tone{0x7a, 0xa2, 0xf7}) {
		t.Errorf("accent %v", wearing.accent)
	}
}
