package cli

import (
	"bytes"
	"regexp"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// eventsAPI answers GET /events with the pages it was given, in turn, and
// keeps what it was asked.
type eventsAPI struct {
	*fakeAPI
	pages []string
	asked []string
}

func (e *eventsAPI) Request(method api.Method, path string, params []api.Param, body any) (api.Value, error) {
	if path != "/events" {
		return e.fakeAPI.Request(method, path, params, body)
	}
	var query []string
	for _, param := range params {
		query = append(query, param.Name+"="+param.Value)
	}
	e.asked = append(e.asked, strings.Join(query, "&"))
	page := e.pages[0]
	if len(e.pages) > 1 {
		e.pages = e.pages[1:]
	}
	return api.MustParse(page), nil
}

func eventsCtx(t *testing.T, pages ...string) (*command.Ctx, *bytes.Buffer, *eventsAPI) {
	t.Helper()
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	var out bytes.Buffer
	var sent []api.Value
	fake := &eventsAPI{pages: pages, fakeAPI: newFakeAPI(`{"/tools": [{"id": 107, "name": "Mail", "type": "mail"}, {"id": 110, "name": "Projects", "type": "boards"}]}`, &sent)}
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")
	ctx.SetAPI(fake)
	return ctx, &out, fake
}

func TestEventsPrintsALinePerEventAndGoesOnWhereItWas(t *testing.T) {
	ctx, out, fake := eventsCtx(t,
		`{"events": [], "cursor": 811, "more": false, "gap": false}`,
		`{"events": [
			{"id": 812, "kind": "card.moved", "ref": "110/44", "data": {"title": "Event stream", "column": "Doing", "moved_from": "To do"}},
			{"id": 813, "kind": "mail.received", "ref": "107/5512", "by": null, "data": {"from": "ann@example.com", "subject": "Lunch?\nSecond line"}}
		 ], "cursor": 815, "more": false, "gap": false}`,
		`{"events": [], "cursor": 815, "more": false, "gap": false}`)

	// A listener that never listened starts where the stream is now
	if err := invoke(ctx, "events"); err != nil || out.String() != "" {
		t.Fatalf("first run: %v, printed %q", err, out.String())
	}
	if err := invoke(ctx, "events"); err != nil {
		t.Fatal(err)
	}
	want := `{"id":812,"kind":"card.moved","ref":"110/44","data":{"title":"Event stream","column":"Doing","moved_from":"To do"}}` + "\n" +
		`{"id":813,"kind":"mail.received","ref":"107/5512","by":null,"data":{"from":"ann@example.com","subject":"Lunch?\nSecond line"}}` + "\n"
	if out.String() != want {
		t.Fatalf("printed %s", out.String())
	}
	if err := invoke(ctx, "events"); err != nil || out.String() != want {
		t.Fatalf("third run: %v, printed %q", err, out.String())
	}

	if got := strings.Join(fake.asked, " | "); got != " | after=811 | after=815" {
		t.Errorf("asked %q", got)
	}
}

func TestEventsAsksForTheToolsKindsAndTimeGiven(t *testing.T) {
	ctx, _, fake := eventsCtx(t, `{"events": [], "cursor": 3, "more": false, "gap": false}`)

	err := invoke(ctx, "events", "--tool", "proj", "--tool", "107", "--kind", "mail", "--kind", "card.moved", "--skip-own", "--since", "2026-10-09T08:00:00+02:00", "--name", "spark")
	if err != nil {
		t.Fatal(err)
	}
	if want := "since=2026-10-09T06:00:00Z&tool[]=110&tool[]=107&kind[]=mail&kind[]=card.moved&skip_own=1"; fake.asked[0] != want {
		t.Errorf("asked %q", fake.asked[0])
	}

	// How long ago is a time too, and each name keeps its own place
	if err := invoke(ctx, "events", "--since", "2h", "--name", "mac"); err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^since=20\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ$`).MatchString(fake.asked[1]) {
		t.Errorf("asked %q", fake.asked[1])
	}
	if err := invoke(ctx, "events", "--name", "spark"); err != nil || fake.asked[2] != "after=3" {
		t.Errorf("asked %q (%v)", fake.asked[2], err)
	}
}

func TestEventsRefusesWhatIsNoNameTimeOrTool(t *testing.T) {
	ctx, _, fake := eventsCtx(t, `{"events": [], "cursor": 3, "more": false, "gap": false}`)

	for _, argv := range [][]string{{"--name", "../up"}, {"--since", "soon"}} {
		if err := invoke(ctx, "events", argv...); err == nil || api.KindOf(err) != api.Usage {
			t.Errorf("%v: %v", argv, err)
		}
	}
	if err := invoke(ctx, "events", "--tool", "nowhere"); err == nil || !strings.Contains(err.Error(), "No tool matches") {
		t.Errorf("got %v", err)
	}
	if len(fake.asked) != 0 {
		t.Errorf("asked %v", fake.asked)
	}
}
