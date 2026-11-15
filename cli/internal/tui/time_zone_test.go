package tui

import (
	"testing"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// startAs starts the app for someone whose profile says this.
func startAs(t *testing.T, profile string) *App {
	t.Helper()
	previous := zone
	t.Cleanup(func() { zone = previous })
	fake := &fakeServer{responses: server().With("/profile", api.MustParse(profile)), calls: &[]call{}, failing: map[string]bool{}}
	app := NewApp(fake, "http://localhost", nil)
	app.launchBrowser = false
	if err := app.Start(); err != nil {
		t.Fatal(err)
	}
	return app
}

func TestTimesAreShownInTheProfilesZoneNotTheComputers(t *testing.T) {
	startAs(t, `{ "id": 1, "name": "Sem", "timezone": "Kiribati", "timezone_identifier": "Pacific/Kiritimati" }`)
	kiritimati, err := time.LoadLocation("Pacific/Kiritimati")
	if err != nil {
		t.Fatal(err)
	}

	moment, ok := local(api.Of("2026-09-24T10:00:00Z"))
	if !ok || moment.Location().String() != "Pacific/Kiritimati" || moment.Format("2006-01-02 15:04") != "2026-09-25 00:00" {
		t.Fatalf("local = %v, %v; want midnight on the 25th in Kiritimati", moment, ok)
	}
	if want := civil(time.Now().In(kiritimati)); !today().Equal(want) {
		t.Fatalf("today = %v; want %v, the date in Kiritimati", today(), want)
	}
	if got := now().Location().String(); got != "Pacific/Kiritimati" {
		t.Fatalf("now is in %s", got)
	}
}

func TestWithoutAZoneTimesStayAsTheServerWroteThem(t *testing.T) {
	startAs(t, `{ "id": 1, "name": "Sem" }`)

	moment, ok := local(api.Of("2026-09-24T10:00:00+05:30"))
	if !ok || moment.Format("15:04") != "10:00" {
		t.Fatalf("local = %v, %v; want 10:00, the server's own clock", moment, ok)
	}
}

func TestAZoneNobodyKnowsIsLikeNoZone(t *testing.T) {
	startAs(t, `{ "id": 1, "name": "Sem", "timezone_identifier": "Mars/Olympus_Mons" }`)

	moment, ok := local(api.Of("2026-09-24T10:00:00+05:30"))
	if !ok || moment.Format("15:04") != "10:00" {
		t.Fatalf("local = %v, %v; want 10:00, the server's own clock", moment, ok)
	}
}
