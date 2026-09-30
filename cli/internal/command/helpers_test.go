package command

import (
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
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
