package command

import (
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// The system the opener runs on; tests swap these.
var (
	goos    = runtime.GOOS
	homeDir = os.UserHomeDir
	// run starts a program and says whether it succeeded. Its output is dropped,
	// so it never draws over the full-screen app.
	run = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
	// output runs a program and returns what it printed.
	output = func(name string, args ...string) (string, error) {
		out, err := exec.Command(name, args...).Output()
		return string(out), err
	}
)

// Open opens link in the installed Dobase app when there is one and link is on
// the server at base, otherwise in the default browser:
//
//  1. DOBASE_APP, or Safari's web app at ~/Applications/Dobase.app (macOS),
//     gets the https link with `open -a`.
//  2. An installed Chrome, Edge or Vivaldi app gets a web+dobase:// link,
//     when one has registered that scheme (they ignore links given to `open -a`).
//  3. The browser gets the https link.
func Open(base, link string) error {
	if path := appPath(base, link); path != "" {
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
// Windows, `xdg-open` elsewhere.
func openWith(link string) error {
	opener, args := "xdg-open", []string{link}
	switch goos {
	case "darwin":
		opener = "open"
	case "windows":
		opener, args = "cmd", []string{"/C", "start", "", link}
	}
	if err := run(opener, args...); err != nil {
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
