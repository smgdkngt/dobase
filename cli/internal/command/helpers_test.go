package command

import (
	"bytes"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

func TestPosterNamesTheAuthorAndHowItWasPosted(t *testing.T) {
	cases := map[string]string{
		`{"user": {"name": "Sophie Chen"}, "via": null, "agent": false}`:     "Sophie Chen",
		`{"user": {"name": "Sophie Chen"}, "via": "Claude", "agent": false}`: "Sophie Chen via Claude",
		`{"user": {"name": "Sophie Chen"}, "via": "Claude", "agent": true}`:  "Claude for Sophie Chen",
		`{"user": null}`: "Former member",
	}
	for body, want := range cases {
		record, err := api.Parse([]byte(body))
		if err != nil {
			t.Fatal(err)
		}
		if got := Poster(record, "Former member"); got != want {
			t.Errorf("Poster(%s) = %q, want %q", body, got, want)
		}
	}
}

func TestTablesAlignWideCharactersByTheCellsTheyTake(t *testing.T) {
	for text, want := range map[string]int{"plan": 4, "日本語": 6, "👍 ok": 5, "café": 4, "e\u0301": 1, "": 0} {
		if got := Width(text); got != want {
			t.Errorf("Width(%q) = %d, want %d", text, got, want)
		}
	}
	if got := Ljust("日本", 6); got != "日本  " {
		t.Errorf("Ljust gave %q", got)
	}

	var out bytes.Buffer
	ctx := NewCtx(&config.Config{}, &out, false, "test")
	ctx.Table([][]string{{"1/7", "報告書", "due 2026-10-01"}, {"1/8", "Report", "due 2026-10-02"}}, 2)
	if want := "  1/7  報告書  due 2026-10-01\n  1/8  Report  due 2026-10-02\n"; out.String() != want {
		t.Errorf("the table is\n%s", out.String())
	}
}
