package command

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// App is Dobase installed as an app of its own: a web app kept by a
// Chromium-family browser in a profile nothing else uses. Its windows, its
// sign-in and its links stay apart from the browser you browse with, also when
// that is the same browser.
type App struct {
	Server   string // the server it shows
	Name     string // what the server calls itself
	Browser  string // the browser's program
	Profile  string // the profile only this app uses
	Manifest string // the app's identity to the browser, from the server's manifest
	ID       string // the browser's id for it, made from that identity
}

// Browsers that keep web apps, the free one first.
var (
	macBrowsers   = []string{"Chromium", "Google Chrome", "Brave Browser", "Microsoft Edge", "Vivaldi"}
	otherBrowsers = []string{"chromium", "chromium-browser", "google-chrome-stable", "google-chrome", "brave-browser", "brave",
		"microsoft-edge-stable", "vivaldi-stable", "vivaldi"}
	// Where a Mac keeps its apps, beside the ones in the home directory.
	macApplications = "/Applications"
	lookPath        = exec.LookPath
)

// How long the browser gets to answer or to start, and to leave once told to.
const (
	browserWait = 90 * time.Second
	leaveWait   = 10 * time.Second
	pause       = 100 * time.Millisecond
)

// appRunning says whether a browser has the profile open: it keeps a lock
// there, a link that names its machine and its process.
var appRunning = func(profile string) bool {
	lock, err := os.Readlink(filepath.Join(profile, "SingletonLock"))
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(lock[strings.LastIndex(lock, "-")+1:])
	return err == nil && alive(pid)
}

// InstallApp makes the Dobase at server an app, kept by browser (a program, an
// app bundle or a name; "" is the first browser found here).
func InstallApp(server, browser string) (App, error) {
	if goos == "windows" {
		return App{}, api.Failf("`dobase app` works on macOS and Linux. On Windows, install Dobase from the browser's own menu.")
	}
	if earlier, found := readApp(); found && earlier.Server != server {
		return App{}, api.Failf("The app here is the one for %s. Run `dobase app remove` first.", earlier.Server)
	}
	program, err := findBrowser(browser)
	if err != nil {
		return App{}, err
	}
	directory, err := appDirectory()
	if err != nil {
		return App{}, err
	}
	app := App{Server: server, Browser: program, Profile: filepath.Join(directory, "app")}

	// Where the browser finds the app: a page that links the manifest and is not
	// a redirect. Nobody is signed in in a new profile, so that is where "/" ends up.
	_, page, err := fetch(server + "/")
	if err != nil {
		return App{}, err
	}
	contents, manifestURL, err := fetch(server + "/manifest.json")
	if err != nil {
		return App{}, err
	}
	manifest, err := api.Parse(contents)
	if err != nil || !manifest.IsObject() {
		return App{}, api.Failf("%s is not a web app manifest, so %s is not a Dobase to install.", manifestURL, server)
	}
	app.Name = manifest.Get("name").Or("Dobase")
	if app.Manifest, err = manifestIdentity(manifestURL, manifest); err != nil {
		return App{}, err
	}
	app.ID = appID(app.Manifest)

	if err := os.MkdirAll(app.Profile, 0o700); err != nil {
		return App{}, api.PathError(app.Profile, err)
	}
	session, err := app.devtools()
	if err != nil {
		return App{}, err
	}
	defer session.close()
	if _, err := session.call("PWA.install", map[string]any{"manifestId": app.Manifest, "installUrlOrBundleUrl": page}); err != nil {
		return App{}, app.refused(err)
	}
	// Installed this way it would open as a tab of the browser
	if _, err := session.call("PWA.changeAppUserSettings", map[string]any{"manifestId": app.Manifest, "displayMode": "standalone"}); err != nil {
		return App{}, app.refused(err)
	}
	return app, app.save()
}

// InstalledApp is the app for server, when `dobase app install` made one here.
func InstalledApp(server string) (App, bool) {
	app, found := readApp()
	return app, found && server != "" && app.Server == strings.TrimRight(server, "/")
}

// Show opens the app, on link when there is one; a running app gets another
// window for it.
func (a App) Show(link string) error {
	// On a Mac the app is a program of its own, which starts its browser out of
	// sight. A browser started from here would sit in the Dock beside it, so the
	// browser only gets the link once the app has it running.
	if shortcut := a.Shortcut(); goos == "darwin" && shortcut != "" {
		if err := run("open", "-a", shortcut); err != nil {
			return fmt.Errorf("open: %w", err)
		}
		if link == "" {
			return nil
		}
		for waited := time.Duration(0); !appRunning(a.Profile) && waited < browserWait; waited += pause {
			time.Sleep(pause)
		}
	}

	args := []string{"--user-data-dir=" + a.Profile, "--app-id=" + a.ID}
	if link != "" {
		// What the browser's own shortcut menus open an app on a page with
		args = append(args, "--app-launch-url-for-shortcuts-menu-item="+link)
	}
	if err := start(a.Browser, args...); err != nil {
		return fmt.Errorf("%s: %w", a.BrowserName(), err)
	}
	return nil
}

// Remove takes the app out of its browser, which removes what the browser put
// on the system, and then deletes its profile.
func (a App) Remove() error {
	// A browser that is gone took its apps along
	if session, err := openDevtools(a.Browser, a.arguments()...); err == nil {
		_, err = session.call("PWA.uninstall", map[string]any{"manifestId": a.Manifest})
		session.close()
		if err == errBrowserLeft {
			return a.refused(err)
		}
	}

	directory, err := appDirectory()
	if err != nil {
		return err
	}
	record := filepath.Join(directory, "app.json")
	if err := os.Remove(record); err != nil && !os.IsNotExist(err) {
		return api.PathError(record, err)
	}
	// Only ever the directory this made
	if a.Profile == filepath.Join(directory, "app") {
		if err := os.RemoveAll(a.Profile); err != nil {
			return api.PathError(a.Profile, err)
		}
	}
	return nil
}

// Shortcut is what the browser put on the system for the app: the app in
// ~/Applications on a Mac, the desktop entry elsewhere. "" when none is found.
func (a App) Shortcut() string {
	home, err := homeDir()
	if err != nil {
		return ""
	}
	if goos != "darwin" {
		entries, _ := filepath.Glob(filepath.Join(home, ".local", "share", "applications", "*-"+a.ID+"-*.desktop"))
		for _, entry := range entries {
			if contents, err := os.ReadFile(entry); err == nil && bytes.Contains(contents, []byte(a.Profile)) {
				return entry
			}
		}
		return ""
	}
	// The browser keeps the apps of every profile in one folder, named apart
	// ("Dobase", "Dobase 1"); this one is the one that names this profile.
	lists, _ := filepath.Glob(filepath.Join(home, "Applications", "*", "*.app", "Contents", "Info.plist"))
	for _, list := range lists {
		contents, err := os.ReadFile(list)
		if err == nil && bytes.Contains(contents, []byte("_crx_"+a.ID)) && bytes.Contains(contents, []byte(a.Profile+"/")) {
			return filepath.Dir(filepath.Dir(list))
		}
	}
	return ""
}

// BrowserName is the browser as people call it: "Vivaldi", "chromium".
func (a App) BrowserName() string { return filepath.Base(a.Browser) }

// arguments start the browser on the app's profile to be told what to do,
// without a window of its own.
func (a App) arguments() []string {
	return []string{"--user-data-dir=" + a.Profile, "--no-first-run", "--no-default-browser-check", "--no-startup-window"}
}

func (a App) devtools() (*devtools, error) {
	session, err := openDevtools(a.Browser, a.arguments()...)
	if err != nil {
		return nil, api.Failf("Could not start %s: %v", a.BrowserName(), err)
	}
	return session, nil
}

// refused explains an error from the browser.
func (a App) refused(err error) error {
	switch {
	case err == errBrowserLeft:
		// A second start on a profile in use hands over to the first one and leaves
		return api.Failf("%s left before it answered. If Dobase is open as an app, quit it and try again.", a.BrowserName())
	case strings.Contains(err.Error(), "wasn't found"):
		return api.Failf("This %s is too old to install an app this way. Update it, or pick another one with --browser.", a.BrowserName())
	}
	return api.Failf("%s: %v", a.BrowserName(), err)
}

func (a App) save() error {
	directory, err := appDirectory()
	if err != nil {
		return err
	}
	record := api.Object("server", a.Server, "name", a.Name, "browser", a.Browser, "profile", a.Profile,
		"manifest", a.Manifest, "id", a.ID).Pretty()
	path := filepath.Join(directory, "app.json")
	if err := os.WriteFile(path, []byte(record+"\n"), 0o600); err != nil {
		return api.PathError(path, err)
	}
	return nil
}

func readApp() (App, bool) {
	directory, err := appDirectory()
	if err != nil {
		return App{}, false
	}
	contents, err := os.ReadFile(filepath.Join(directory, "app.json"))
	if err != nil {
		return App{}, false
	}
	record, err := api.Parse(contents)
	if err != nil {
		return App{}, false
	}
	app := App{Server: record.Get("server").S(), Name: record.Get("name").Or("Dobase"), Browser: record.Get("browser").S(),
		Profile: record.Get("profile").S(), Manifest: record.Get("manifest").S(), ID: record.Get("id").S()}
	return app, app.Server != "" && app.Browser != "" && app.Profile != "" && app.ID != ""
}

// appDirectory is where the app's profile and what is known about it are kept.
func appDirectory() (string, error) {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, err := homeDir()
		if err != nil {
			return "", api.Failf("Could not find your home directory: %v", err)
		}
		base = filepath.Join(home, ".local", "share")
	}
	return filepath.Join(base, "dobase"), nil
}

// findBrowser is the program of the browser asked for, or of the first one here.
func findBrowser(asked string) (string, error) {
	if asked != "" {
		if strings.HasSuffix(strings.TrimRight(asked, "/"), ".app") {
			asked = macProgram(strings.TrimRight(asked, "/"))
		}
		program, err := lookPath(asked)
		if err != nil {
			return "", api.Failf("No browser at %s.", Quoted(asked))
		}
		return program, nil
	}

	if goos == "darwin" {
		folders := []string{macApplications}
		if home, err := homeDir(); err == nil {
			folders = append(folders, filepath.Join(home, "Applications"))
		}
		for _, name := range macBrowsers {
			for _, folder := range folders {
				if program, err := lookPath(macProgram(filepath.Join(folder, name+".app"))); err == nil {
					return program, nil
				}
			}
		}
	} else {
		for _, name := range otherBrowsers {
			if program, err := lookPath(name); err == nil {
				return program, nil
			}
		}
	}
	return "", api.Failf("No Chromium, Chrome, Brave, Edge or Vivaldi found here. Install one, or point at yours with --browser.")
}

// macProgram is the program inside an app bundle, which carries the bundle's name.
func macProgram(bundle string) string {
	return filepath.Join(bundle, "Contents", "MacOS", strings.TrimSuffix(filepath.Base(bundle), ".app"))
}

// fetch gets a page the way a browser nobody is signed in to would, and says
// where it ended up after redirects.
func fetch(address string) ([]byte, string, error) {
	client := http.Client{Timeout: 30 * time.Second}
	response, err := client.Get(address)
	if err != nil {
		return nil, "", api.Failf("Could not reach %s: %v", address, err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil || response.StatusCode >= 400 {
		return nil, "", api.Failf("Could not read %s (%s).", address, response.Status)
	}
	return body, response.Request.URL.String(), nil
}

// manifestIdentity is the id a browser gives the app of a manifest: its start
// page, or its "id" counted from the top of that page's site.
func manifestIdentity(manifestURL string, manifest api.Value) (string, error) {
	identity, err := url.Parse(manifestURL)
	if err == nil {
		identity, err = identity.Parse(manifest.Get("start_url").Or("."))
	}
	if id := manifest.Get("id").S(); err == nil && id != "" {
		identity, err = (&url.URL{Scheme: identity.Scheme, Host: identity.Host, Path: "/"}).Parse(id)
	}
	if err != nil {
		return "", api.Failf("The manifest at %s has an address in it that isn't one: %v", manifestURL, err)
	}
	identity.Fragment = ""
	return identity.String(), nil
}

// appID is Chromium's id for the web app with this identity: the hash of its
// hash, the first 16 bytes written in the letters a to p.
func appID(identity string) string {
	once := sha256.Sum256([]byte(identity))
	twice := sha256.Sum256(once[:])
	id := make([]byte, 0, 32)
	for _, b := range twice[:16] {
		id = append(id, 'a'+b>>4, 'a'+b&0xf)
	}
	return string(id)
}

// -- The browser's debugging pipe --------------------------------------------------

var errBrowserLeft = errors.New("the browser left")

// devtools is a browser being told what to do over its debugging pipe: JSON
// messages that end in a zero byte, in on its file 3 and out on its file 4.
type devtools struct {
	process *exec.Cmd
	to      *os.File
	replies chan api.Value
	left    chan struct{}
	calls   int64
}

func openDevtools(browser string, args ...string) (*devtools, error) {
	toRead, toWrite, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	fromRead, fromWrite, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	process := exec.Command(browser, append(args, "--remote-debugging-pipe")...)
	process.ExtraFiles = []*os.File{toRead, fromWrite}
	err = process.Start()
	toRead.Close()
	fromWrite.Close()
	if err != nil {
		toWrite.Close()
		fromRead.Close()
		return nil, err
	}

	session := &devtools{process: process, to: toWrite, replies: make(chan api.Value), left: make(chan struct{})}
	go func() {
		defer close(session.replies)
		defer fromRead.Close()
		reader := bufio.NewReader(fromRead)
		for {
			message, err := reader.ReadBytes(0)
			if err != nil {
				return
			}
			if reply, err := api.Parse(message[:len(message)-1]); err == nil && reply.Has("id") {
				session.replies <- reply
			}
		}
	}()
	go func() {
		process.Wait()
		close(session.left)
	}()
	return session, nil
}

// call asks the browser to do something and waits for what came of it.
func (d *devtools) call(method string, params map[string]any) (api.Value, error) {
	d.calls++
	message := api.Object("id", d.calls, "method", method, "params", params).JSON()
	if _, err := d.to.WriteString(message + "\x00"); err != nil {
		return api.Null, errBrowserLeft
	}
	timeout := time.After(browserWait)
	for {
		select {
		case reply, open := <-d.replies:
			switch {
			case !open:
				return api.Null, errBrowserLeft
			case reply.Get("id").Int() != d.calls:
			case reply.Has("error"):
				return api.Null, fmt.Errorf("%s", reply.Get("error", "message").Or(method+" failed"))
			default:
				return reply.Get("result"), nil
			}
		case <-timeout:
			return api.Null, fmt.Errorf("no answer to %s within %v", method, browserWait)
		}
	}
}

// close tells the browser to leave, and makes it when it doesn't.
func (d *devtools) close() {
	d.calls++
	d.to.WriteString(api.Object("id", d.calls, "method", "Browser.close").JSON() + "\x00")
	d.to.Close()
	go func() {
		for range d.replies {
		}
	}()
	select {
	case <-d.left:
	case <-time.After(leaveWait):
		d.process.Process.Kill()
		<-d.left
	}
}
