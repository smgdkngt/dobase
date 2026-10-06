package command

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"
)

// fakeSystem records the programs Open starts; handled lists the commands that succeed.
func fakeSystem(t *testing.T, system string, handled ...string) *[]string {
	t.Helper()
	home := t.TempDir()
	started := &[]string{}
	oldGoos, oldHome, oldRun, oldStart, oldOutput, oldRunning := goos, homeDir, run, start, output, appRunning
	t.Cleanup(func() {
		goos, homeDir, run, start, output, appRunning = oldGoos, oldHome, oldRun, oldStart, oldOutput, oldRunning
	})
	t.Setenv("DOBASE_APP", "")
	t.Setenv("XDG_DATA_HOME", "")

	goos = system
	homeDir = func() (string, error) { return home, nil }
	succeeds := func(command string) error {
		*started = append(*started, command)
		for _, prefix := range handled {
			if strings.HasPrefix(command, prefix) {
				return nil
			}
		}
		return errors.New("exit status 1")
	}
	run = func(name string, args ...string) error { return succeeds(name + " " + strings.Join(args, " ")) }
	start = run
	output = func(name string, args ...string) (string, error) {
		if err := succeeds(name + " " + strings.Join(args, " ")); err != nil {
			return "", err
		}
		return "vivaldi-dobase.desktop\n", nil
	}
	return started
}

func installSafariApp(t *testing.T) string {
	home, _ := homeDir()
	app := filepath.Join(home, "Applications", "Dobase.app")
	if err := os.MkdirAll(filepath.Join(app, "Contents"), 0o755); err != nil {
		t.Fatal(err)
	}
	plist := `<plist><dict><key>CFBundleIdentifier</key><string>com.apple.Safari.WebApp.1234</string></dict></plist>`
	if err := os.WriteFile(filepath.Join(app, "Contents", "Info.plist"), []byte(plist), 0o644); err != nil {
		t.Fatal(err)
	}
	return app
}

const draft = "https://dobase.test/tools/8/mails/new?draft_id=400"

func TestOpenHandsServerLinksToSafarisWebApp(t *testing.T) {
	started := fakeSystem(t, "darwin", "open -a")
	app := installSafariApp(t)

	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	if want := []string{"open -a " + app + " " + draft}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}
}

func TestOpenTriesTheAppSchemeThenTheBrowser(t *testing.T) {
	started := fakeSystem(t, "darwin", "open https:")
	if err := Open("https://dobase.test/", draft); err != nil {
		t.Fatal(err)
	}
	want := []string{"open web+dobase://tools/8/mails/new?draft_id=400", "open " + draft}
	if !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}

	started = fakeSystem(t, "darwin", "open web+dobase:")
	if err := Open("https://dobase.test/", draft); err != nil || len(*started) != 1 {
		t.Errorf("started %q, %v", *started, err)
	}
}

func TestOpenSendsOtherLinksStraightToTheBrowser(t *testing.T) {
	started := fakeSystem(t, "darwin", "open")
	installSafariApp(t)

	for _, link := range []string{"https://example.com/tools/8", "http://dobase.test/tools/8", "https://dobase.test.evil/x"} {
		*started = nil
		if err := Open("https://dobase.test", link); err != nil {
			t.Fatal(err)
		}
		if want := []string{"open " + link}; !reflect.DeepEqual(*started, want) {
			t.Errorf("%s: started %q", link, *started)
		}
	}
}

func TestDobaseAppPicksTheAppOnAMac(t *testing.T) {
	started := fakeSystem(t, "darwin", "open")
	t.Setenv("DOBASE_APP", "/Applications/Our Tools.app")

	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	if want := []string{"open -a /Applications/Our Tools.app " + draft}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}
}

func TestOpenOnlyUsesTheSchemeElsewhereWhenSomethingRegisteredIt(t *testing.T) {
	started := fakeSystem(t, "linux", "xdg-open https:")
	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	want := []string{"xdg-mime query default x-scheme-handler/web+dobase", "xdg-open " + draft}
	if !reflect.DeepEqual(*started, want) {
		t.Errorf("linux without a handler: started %q", *started)
	}

	started = fakeSystem(t, "linux", "xdg-mime", "xdg-open web+dobase:")
	if err := Open("https://dobase.test", draft); err != nil || (*started)[1] != "xdg-open web+dobase://tools/8/mails/new?draft_id=400" {
		t.Errorf("linux with a handler: started %q, %v", *started, err)
	}

	started = fakeSystem(t, "windows", "cmd")
	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	want = []string{`reg query HKCU\Software\Classes\web+dobase`, "cmd /C start  " + draft}
	if !reflect.DeepEqual(*started, want) {
		t.Errorf("windows without a handler: started %q", *started)
	}
}

func TestOpenFailsWhenNothingOpens(t *testing.T) {
	fakeSystem(t, "linux")
	if err := Open("https://dobase.test", "https://example.com"); err == nil || !strings.HasPrefix(err.Error(), "xdg-open: ") {
		t.Errorf("got %v", err)
	}
}

func TestOpenDoesNotWaitForXdgOpen(t *testing.T) {
	started := fakeSystem(t, "linux", "xdg-open")
	// xdg-open can stay around as long as the browser it started
	run = func(name string, args ...string) error {
		t.Errorf("waited for %s to finish", name)
		return nil
	}

	if err := Open("https://dobase.test", "https://example.com/x"); err != nil {
		t.Fatal(err)
	}
	if want := []string{"xdg-open https://example.com/x"}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}
}

func TestAStartedProgramIsNotWaitedForButAQuickFailureShows(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("needs sleep and false")
	}
	began := time.Now()
	if err := start("sleep", "5"); err != nil {
		t.Fatal(err)
	}
	if waited := time.Since(began); waited > 3*time.Second {
		t.Errorf("waited %v for a program that keeps running", waited)
	}
	if err := start("false"); err == nil {
		t.Error("a program that fails right away counted as started")
	}
	if err := start("dobase-no-such-program"); err == nil {
		t.Error("a program that isn't there counted as started")
	}
}
