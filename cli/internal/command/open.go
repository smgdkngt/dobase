package command

import (
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// startWait is how long a started program gets to fail before it's left running.
const startWait = time.Second

// The system the opener runs on; tests swap these.
var (
	goos    = runtime.GOOS
	homeDir = os.UserHomeDir
	// run starts a program and says whether it succeeded. Its output is dropped,
	// so it never draws over the full-screen app.
	run = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
	// start starts a program that may keep running, as xdg-open does while the
	// browser it started is open. It waits a moment, to tell when the program
	// fails right away, and then lets it be: the program outlives the terminal
	// this ran in.
	start = func(name string, args ...string) error {
		command := exec.Command(name, args...)
		detach(command)
		if err := command.Start(); err != nil {
			return err
		}
		done := make(chan error, 1)
		go func() { done <- command.Wait() }()
		select {
		case err := <-done:
			return err
		case <-time.After(startWait):
			return nil
		}
	}
	// output runs a program and returns what it printed.
	output = func(name string, args ...string) (string, error) {
		out, err := exec.Command(name, args...).Output()
		return string(out), err
	}
)

// Open opens link in the installed Dobase app when there is one and link is on
// the server at base, otherwise in the default browser:
//
//  1. The app `dobase app install` made is handed it, unless DOBASE_APP names
//     another app.
//  2. DOBASE_APP, or Safari's web app at ~/Applications/Dobase.app (macOS),
//     gets the https link with `open -a`.
//  3. An installed Chrome, Edge or Vivaldi app gets a web+dobase:// link,
//     when one has registered that scheme (they ignore links given to `open -a`).
//  4. The browser gets the https link.
func Open(base, link string) error {
	if path := appPath(base, link); path != "" {
		if app, found := InstalledApp(base); found && os.Getenv("DOBASE_APP") == "" && app.Show(link) == nil {
			return nil
		}
		if app := macApp(); app != "" && run("open", "-a", app, link) == nil {
			return nil
		}
		if schemeHandled() && openWith("web+dobase://"+path) == nil {
			return nil
		}
	}
	return openWith(link)
}

// openWith opens link with the system's opener: `open` on macOS, `start` on
// Windows, `xdg-open` elsewhere. The first two hand the link over and are done;
// xdg-open isn't waited for.
func openWith(link string) error {
	opener, args, launch := "xdg-open", []string{link}, start
	switch goos {
	case "darwin":
		opener, launch = "open", run
	case "windows":
		opener, args, launch = "cmd", []string{"/C", "start", "", link}, run
	}
	if err := launch(opener, args...); err != nil {
		return fmt.Errorf("%s: %w", opener, err)
	}
	return nil
}

// appPath is link's path and query without the leading slash when link is on
// the server at base, else "".
func appPath(base, link string) string {
	server, err := url.Parse(strings.TrimRight(base, "/") + "/")
	if err != nil || base == "" {
		return ""
	}
	target, err := url.Parse(link)
	if err != nil || target.Scheme != server.Scheme || target.Host != server.Host || !strings.HasPrefix(target.Path, server.Path) {
		return ""
	}
	path := strings.TrimPrefix(target.Path, "/")
	if target.RawQuery != "" {
		path += "?" + target.RawQuery
	}
	if target.Fragment != "" {
		path += "#" + target.Fragment
	}
	return path
}

// macApp is the app `open -a` should hand links to: DOBASE_APP, or Safari's web
// app for Dobase. Chromium apps are left out, they open their last page instead.
func macApp() string {
	if goos != "darwin" {
		return ""
	}
	if app := os.Getenv("DOBASE_APP"); app != "" {
		return app
	}
	home, err := homeDir()
	if err != nil {
		return ""
	}
	app := filepath.Join(home, "Applications", "Dobase.app")
	info, err := os.ReadFile(filepath.Join(app, "Contents", "Info.plist"))
	if err != nil || !strings.Contains(string(info), "com.apple.Safari.WebApp") {
		return ""
	}
	return app
}

// schemeHandled says whether an app may have registered web+dobase://. macOS
// just fails to open a scheme nobody handles; Windows would show a dialog and
// xdg-open would try a browser, so those are asked first.
func schemeHandled() bool {
	switch goos {
	case "darwin":
		return true
	case "windows":
		return run("reg", "query", `HKCU\Software\Classes\web+dobase`) == nil
	}
	handler, err := output("xdg-mime", "query", "default", "x-scheme-handler/web+dobase")
	return err == nil && strings.TrimSpace(handler) != ""
}
