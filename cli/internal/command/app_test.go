package command

import (
	"bufio"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// The tests' browser is this test program started over: with DOBASE_TEST_BROWSER
// set it writes down how it was started and what it is told over the debugging
// pipe, and answers the way DOBASE_TEST_BROWSER_SAYS has it.
func TestMain(m *testing.M) {
	if log := os.Getenv("DOBASE_TEST_BROWSER"); log != "" {
		actAsBrowser(log, os.Getenv("DOBASE_TEST_BROWSER_SAYS"))
		return
	}
	os.Exit(m.Run())
}

func actAsBrowser(log, says string) {
	written, err := os.OpenFile(log, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		os.Exit(1)
	}
	defer written.Close()
	written.WriteString("started " + strings.Join(os.Args[1:], " ") + "\n")
	if says == "leaves" || !strings.Contains(strings.Join(os.Args, " "), "--remote-debugging-pipe") {
		return
	}

	in, out := bufio.NewReader(os.NewFile(3, "in")), os.NewFile(4, "out")
	for {
		message, err := in.ReadBytes(0)
		if err != nil {
			return
		}
		call, _ := api.Parse(message[:len(message)-1])
		method := call.Get("method").S()
		written.WriteString(method + " " + call.Get("params").JSON() + "\n")

		reply := api.Object("id", call.Get("id"), "result", map[string]any{})
		if method == "PWA.install" && says != "" {
			reply = api.Object("id", call.Get("id"), "error", map[string]any{"code": -32601, "message": says})
		}
		// Something nobody asked about comes first, as a browser's events do
		out.WriteString(`{"method":"Target.targetCreated","params":{}}` + "\x00" + reply.JSON() + "\x00")
		if method == "Browser.close" {
			return
		}
	}
}

// testBrowser makes this test program the browser, and returns what it wrote down.
func testBrowser(t *testing.T, says string) (program string, told func() []string) {
	t.Helper()
	log := filepath.Join(t.TempDir(), "browser.log")
	t.Setenv("DOBASE_TEST_BROWSER", log)
	t.Setenv("DOBASE_TEST_BROWSER_SAYS", says)
	return os.Args[0], func() []string {
		contents, _ := os.ReadFile(log)
		return strings.Split(strings.TrimSpace(string(contents)), "\n")
	}
}

// dobaseServer is a Dobase nobody is signed in to: the front page sends you to sign in.
func dobaseServer(t *testing.T, manifest string) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/":
			http.Redirect(w, r, "/session/new", http.StatusFound)
		case "/session/new":
			w.Write([]byte(`<link rel="manifest" href="/manifest.json">`))
		case "/manifest.json":
			w.Write([]byte(manifest))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	return server.URL
}

const manifest = `{"name": "Our Tools", "start_url": "/", "display": "standalone"}`

func TestInstallAppHasTheBrowserInstallWhatTheServerOffersInAProfileOfItsOwn(t *testing.T) {
	fakeSystem(t, "linux")
	home, _ := homeDir()
	browser, told := testBrowser(t, "")
	server := dobaseServer(t, manifest)

	app, err := InstallApp(server, browser)
	if err != nil {
		t.Fatal(err)
	}
	profile := filepath.Join(home, ".local", "share", "dobase", "app")
	want := []string{
		"started --user-data-dir=" + profile + " --no-first-run --no-default-browser-check --no-startup-window --remote-debugging-pipe",
		`PWA.install {"installUrlOrBundleUrl":"` + server + `/session/new","manifestId":"` + server + `/"}`,
		`PWA.changeAppUserSettings {"displayMode":"standalone","manifestId":"` + server + `/"}`,
		"Browser.close null",
	}
	if got := told(); !reflect.DeepEqual(got, want) {
		t.Errorf("the browser was told\n%s\nnot\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	if app.Name != "Our Tools" || app.Profile != profile || app.ID != appID(server+"/") {
		t.Errorf("app %+v", app)
	}

	kept, found := InstalledApp(server + "/")
	if !found || kept != app {
		t.Errorf("kept %+v, %v", kept, found)
	}
	if _, found := InstalledApp("https://elsewhere.test"); found {
		t.Error("the app counts for another server too")
	}
	if _, err := InstallApp("https://elsewhere.test", browser); err == nil || !strings.Contains(err.Error(), "dobase app remove") {
		t.Errorf("a second server: %v", err)
	}
}

func TestInstallAppSaysWhyTheBrowserDidNot(t *testing.T) {
	for says, want := range map[string]string{
		"Couldn't fetch install info": "Couldn't fetch install info",
		"'PWA.install' wasn't found":  "too old to install an app",
		"leaves":                      "quit it and try again",
	} {
		fakeSystem(t, "linux")
		browser, _ := testBrowser(t, says)
		server := dobaseServer(t, manifest)

		_, err := InstallApp(server, browser)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: %v", says, err)
		}
		if _, found := InstalledApp(server); found {
			t.Errorf("%s: an app is kept all the same", says)
		}
	}
}

func TestInstallAppNeedsABrowserThatIsHereAndAServerThatIsADobase(t *testing.T) {
	fakeSystem(t, "linux")
	oldLook, oldApplications := lookPath, macApplications
	t.Cleanup(func() { lookPath, macApplications = oldLook, oldApplications })
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	macApplications = t.TempDir()
	server := dobaseServer(t, manifest)

	if _, err := InstallApp(server, ""); err == nil || !strings.Contains(err.Error(), "--browser") {
		t.Errorf("no browser: %v", err)
	}
	if _, err := InstallApp(server, "netscape"); err == nil || !strings.Contains(err.Error(), `No browser at "netscape"`) {
		t.Errorf("a browser that isn't here: %v", err)
	}

	lookPath = func(name string) (string, error) { return name, nil }
	goos = "darwin"
	if program, _ := findBrowser(""); program != filepath.Join(macApplications, "Chromium.app", "Contents", "MacOS", "Chromium") {
		t.Errorf("on a Mac it found %s", program)
	}
	if program, _ := findBrowser("/Applications/Brave Browser.app/"); program != "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" {
		t.Errorf("an app bundle became %s", program)
	}

	browser, told := testBrowser(t, "")
	if _, err := InstallApp(dobaseServer(t, "<html>"), browser); err == nil || !strings.Contains(err.Error(), "not a web app manifest") {
		t.Errorf("no manifest: %v", err)
	}
	goos = "windows"
	if _, err := InstallApp(server, browser); err == nil || !strings.Contains(err.Error(), "macOS and Linux") {
		t.Errorf("windows: %v", err)
	}
	if got := told(); got[0] != "" {
		t.Errorf("the browser was started: %q", got)
	}
}

func TestTheAppsIdentityIsTheOneABrowserGivesIt(t *testing.T) {
	// What Vivaldi and Chrome call the app of app.dobase.co
	if id := appID("https://app.dobase.co/"); id != "fapenbnbeacoicjbbcdidmbgdjlgdfij" {
		t.Errorf("id %s", id)
	}
	for _, c := range []struct{ manifest, want string }{
		{`{"start_url": "/"}`, "https://dobase.test/"},
		{`{}`, "https://dobase.test/work/"},
		{`{"start_url": "home?from=app#top"}`, "https://dobase.test/work/home?from=app"},
		{`{"start_url": "/work/home", "id": "dobase"}`, "https://dobase.test/dobase"},
		{`{"start_url": "https://app.dobase.test/", "id": "/"}`, "https://app.dobase.test/"},
	} {
		got, err := manifestIdentity("https://dobase.test/work/manifest.json", api.MustParse(c.manifest))
		if err != nil || got != c.want {
			t.Errorf("%s: %s, %v", c.manifest, got, err)
		}
	}
}

// installedApp is an app as InstallApp leaves it, with what its browser put on the system.
func installedApp(t *testing.T, server string) App {
	t.Helper()
	home, _ := homeDir()
	app := App{Server: server, Name: "Dobase", Browser: "/browsers/chromium", Manifest: server + "/", ID: appID(server + "/"),
		Profile: filepath.Join(home, ".local", "share", "dobase", "app")}
	if err := os.MkdirAll(app.Profile, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := app.save(); err != nil {
		t.Fatal(err)
	}
	return app
}

func macShortcut(t *testing.T, name, id, profile string) string {
	t.Helper()
	home, _ := homeDir()
	shortcut := filepath.Join(home, "Applications", "Chromium Apps.localized", name+".app")
	if err := os.MkdirAll(filepath.Join(shortcut, "Contents"), 0o755); err != nil {
		t.Fatal(err)
	}
	list := "<key>CrAppModeShortcutID</key><string>" + id + "</string>" +
		"<key>CrAppModeUserDataDir</key><string>" + profile + "/-/Web Applications/_crx_" + id + "</string>"
	if err := os.WriteFile(filepath.Join(shortcut, "Contents", "Info.plist"), []byte(list), 0o644); err != nil {
		t.Fatal(err)
	}
	return shortcut
}

func TestOpenGivesServerLinksToTheInstalledApp(t *testing.T) {
	started := fakeSystem(t, "linux", "/browsers/chromium")
	app := installedApp(t, "https://dobase.test")

	if err := Open("https://dobase.test/", draft); err != nil {
		t.Fatal(err)
	}
	want := []string{"/browsers/chromium --user-data-dir=" + app.Profile + " --app-id=" + app.ID + " --app-launch-url-for-shortcuts-menu-item=" + draft}
	if !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}

	*started = nil
	if err := app.Show(""); err != nil {
		t.Fatal(err)
	}
	if want := []string{"/browsers/chromium --user-data-dir=" + app.Profile + " --app-id=" + app.ID}; !reflect.DeepEqual(*started, want) {
		t.Errorf("without a link it started %q", *started)
	}

	// Another server's pages are not the app's
	*started = nil
	if err := Open("https://dobase.test", "https://example.com/tools/8"); err == nil || len(*started) != 1 || (*started)[0] != "xdg-open https://example.com/tools/8" {
		t.Errorf("elsewhere: started %q, %v", *started, err)
	}
}

func TestOnAMacTheAppStartsItsBrowserAndThenGetsTheLink(t *testing.T) {
	started := fakeSystem(t, "darwin", "open -a", "/browsers/chromium")
	app := installedApp(t, "https://dobase.test")
	// The same site installed from the browser's everyday profile lies beside it
	macShortcut(t, "Dobase", app.ID, "/Users/someone/Library/Application Support/Chromium")
	shortcut := macShortcut(t, "Dobase 1", app.ID, app.Profile)
	asked := 0
	appRunning = func(profile string) bool {
		asked++
		return profile == app.Profile && asked > 2
	}

	if got := app.Shortcut(); got != shortcut {
		t.Fatalf("its shortcut is %s", got)
	}
	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	want := []string{"open -a " + shortcut,
		"/browsers/chromium --user-data-dir=" + app.Profile + " --app-id=" + app.ID + " --app-launch-url-for-shortcuts-menu-item=" + draft}
	if !reflect.DeepEqual(*started, want) || asked != 3 {
		t.Errorf("started %q after asking %d times", *started, asked)
	}

	*started = nil
	if err := app.Show(""); err != nil || !reflect.DeepEqual(*started, want[:1]) {
		t.Errorf("without a link it started %q, %v", *started, err)
	}

	// DOBASE_APP names another app to use
	*started = nil
	t.Setenv("DOBASE_APP", "/Applications/Our Tools.app")
	if err := Open("https://dobase.test", draft); err != nil || !reflect.DeepEqual(*started, []string{"open -a /Applications/Our Tools.app " + draft}) {
		t.Errorf("with DOBASE_APP it started %q, %v", *started, err)
	}
}

func TestOpenGoesOnToTheBrowserWhenTheAppDoesNotStart(t *testing.T) {
	started := fakeSystem(t, "linux", "xdg-open https:")
	installedApp(t, "https://dobase.test")

	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	if last := (*started)[len(*started)-1]; len(*started) != 3 || last != "xdg-open "+draft {
		t.Errorf("started %q", *started)
	}
}

func TestAppRunningReadsTheBrowsersLock(t *testing.T) {
	profile := t.TempDir()
	if appRunning(profile) {
		t.Error("a profile without a lock counts as open")
	}
	for target, want := range map[string]bool{"a-mac.local-" + itoa(os.Getpid()): true, "a-mac.local-0x": false, "nonsense": false} {
		lock := filepath.Join(profile, "SingletonLock")
		os.Remove(lock)
		if err := os.Symlink(target, lock); err != nil {
			t.Skip("no symlinks here")
		}
		if got := appRunning(profile); got != want {
			t.Errorf("%s: %v", target, got)
		}
	}
}

func TestRemoveTakesTheAppOutOfItsBrowserAndForgetsIt(t *testing.T) {
	fakeSystem(t, "linux")
	browser, told := testBrowser(t, "")
	app := installedApp(t, "https://dobase.test")
	app.Browser = browser
	os.WriteFile(filepath.Join(app.Profile, "Cookies"), []byte("signed in"), 0o600)

	if err := app.Remove(); err != nil {
		t.Fatal(err)
	}
	if got := told(); len(got) != 3 || got[1] != `PWA.uninstall {"manifestId":"https://dobase.test/"}` {
		t.Errorf("the browser was told %q", got)
	}
	if _, found := InstalledApp("https://dobase.test"); found {
		t.Error("it is still kept")
	}
	if _, err := os.Stat(app.Profile); !os.IsNotExist(err) {
		t.Errorf("its profile is still there: %v", err)
	}

	// A profile in use is left alone
	t.Setenv("DOBASE_TEST_BROWSER_SAYS", "leaves")
	app = installedApp(t, "https://dobase.test")
	app.Browser = browser
	if err := app.Remove(); err == nil || !strings.Contains(err.Error(), "quit it") {
		t.Errorf("while it runs: %v", err)
	}
	if _, err := os.Stat(app.Profile); err != nil {
		t.Errorf("its profile went all the same: %v", err)
	}
}

func itoa(number int) string { return api.Of(number).JSON() }
