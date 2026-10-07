package command

import (
	"bytes"
	"embed"
	"fmt"
	"image"
	"image/png"
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

// App is Dobase installed as an app of its own: an Electron that shows the
// server's pages and nothing else. To the system it is a program apart, with
// the server's icon and a sign-in of its own, so the browser you browse with
// has no part in it; links to other sites go to that browser.
type App struct {
	Server   string // the server it shows
	Name     string // what the server calls itself
	Path     string // the app on this system: the bundle on a Mac, the desktop entry elsewhere
	Program  string // what runs it: the Electron in the bundle, or the system's own
	Code     string // the app's scripts, which Electron is started on
	Data     string // where it keeps its sign-in
	Electron string // the version of the Electron it came with; "" when the system keeps that
	// An app of the earlier kind, kept by a browser. It can only be removed.
	earlier *browserApp
}

// The app's scripts: what Electron is started on.
//
//go:embed shell/main.js shell/links.js shell/preload.js
var shell embed.FS

// What a Mac knows the app by.
const bundleID = "co.dobase.app"

var lookPath = exec.LookPath

// appRunning says whether the app has its data open: it keeps a lock there, a
// link that names its machine and its process.
var appRunning = func(data string) bool {
	lock, err := os.Readlink(filepath.Join(data, "SingletonLock"))
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(lock[strings.LastIndex(lock, "-")+1:])
	return err == nil && alive(pid)
}

// InstallApp makes the Dobase at server an app here, or brings the one that is
// here up to date; its sign-in stays. electron is an Electron of your own (its
// zip, or elsewhere than on a Mac its program); "" is the system's own when
// there is one, and else the newest release. tell hears what takes a while.
func InstallApp(server, electron string, tell func(string)) (App, error) {
	if goos == "windows" {
		return App{}, api.Failf("`dobase app` works on macOS and Linux. On Windows, install Dobase from the browser's own menu.")
	}
	before, had := readApp()
	switch {
	case !had:
	case before.earlier != nil:
		return App{}, api.Failf("Dobase is an app here the earlier way, kept by %s. `dobase app remove` takes that one away with the sign-in it kept; then install again.", filepath.Base(before.earlier.Browser))
	case before.Server != server:
		return App{}, api.Failf("The app here is the one for %s. Run `dobase app remove` first.", before.Server)
	case appRunning(before.Data):
		return App{}, api.Failf("%s is open. Quit it and try again.", before.Name)
	}
	directory, err := appDirectory()
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
	icon, picture, err := appIcon(manifestURL, manifest)
	if err != nil {
		return App{}, err
	}
	app := App{Server: server, Name: manifest.Get("name").Or("Dobase"), Data: filepath.Join(directory, "data")}
	if err := os.MkdirAll(app.Data, 0o700); err != nil {
		return App{}, api.PathError(app.Data, err)
	}

	// The Electron: yours, the system's, or the newest release
	archive := ""
	switch {
	case strings.HasSuffix(electron, ".zip"):
		archive = electron
	case electron != "" && goos == "darwin":
		return App{}, api.Failf("On a Mac --electron takes Electron's zip, which the app is made from.")
	case electron != "":
		if app.Program, err = lookPath(electron); err != nil {
			return App{}, api.Failf("No Electron at %s.", Quoted(electron))
		}
	case goos != "darwin":
		app.Program, _ = lookPath("electron")
	}
	if archive == "" && app.Program == "" {
		if archive, app.Electron, err = fetchElectron(directory, tell); err != nil {
			return App{}, err
		}
		defer os.Remove(archive)
	}

	if goos == "darwin" {
		err = app.makeBundle(archive, picture)
	} else {
		err = app.makeDesktopEntry(directory, archive, icon)
	}
	if err != nil {
		return App{}, err
	}
	// A server that changed its name leaves no app under the old one
	if had && before.Path != app.Path && goos == "darwin" && isOurBundle(before.Path) {
		os.RemoveAll(before.Path)
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
	if a.earlier != nil {
		return api.Failf("This app is of the earlier kind, which `dobase` no longer opens. `dobase app remove` and `dobase app install` make it the new one.")
	}
	if goos == "darwin" {
		// The system starts the app, or hands a running one the link
		args := []string{"-a", a.Path}
		if path := appPath(a.Server, link); path != "" {
			args = append(args, "web+dobase://"+path)
		}
		if err := run("open", args...); err != nil {
			return fmt.Errorf("open: %w", err)
		}
		return nil
	}
	// A second start hands its link to the first and leaves
	args := []string{a.Code}
	if link != "" {
		args = append(args, link)
	}
	if err := start(a.Program, args...); err != nil {
		return fmt.Errorf("%s: %w", filepath.Base(a.Program), err)
	}
	return nil
}

// Remove takes the app off the system, with the sign-in it kept.
func (a App) Remove() error {
	directory, err := appDirectory()
	if err != nil {
		return err
	}
	if a.earlier != nil {
		if err := a.earlier.remove(directory); err != nil {
			return err
		}
	} else {
		if appRunning(a.Data) {
			return api.Failf("%s is open. Quit it and try again.", a.Name)
		}
		// Only ever what this made
		gone := []string{filepath.Join(directory, "shell"), filepath.Join(directory, "electron"), filepath.Join(directory, "data")}
		if goos != "darwin" {
			gone = append(gone, desktopEntry(directory), desktopIcon(directory))
		} else if isOurBundle(a.Path) {
			gone = append(gone, a.Path)
		}
		for _, path := range gone {
			if err := os.RemoveAll(path); err != nil {
				return api.PathError(path, err)
			}
		}
	}
	record := filepath.Join(directory, "app.json")
	if err := os.Remove(record); err != nil && !os.IsNotExist(err) {
		return api.PathError(record, err)
	}
	return nil
}

// makeBundle makes the app a Mac's own kind of program: Electron's bundle under
// the app's name, with its icon and its scripts, in ~/Applications.
func (a *App) makeBundle(archive string, picture image.Image) error {
	home, err := homeDir()
	if err != nil {
		return api.Failf("Could not find your home directory: %v", err)
	}
	applications := filepath.Join(home, "Applications")
	a.Path = filepath.Join(applications, strings.NewReplacer("/", "-", ":", "-").Replace(a.Name)+".app")
	if _, err := os.Stat(a.Path); err == nil && !isOurBundle(a.Path) {
		return api.Failf("%s is another app. Move it away, or remove it, and try again.", a.Path)
	}
	if err := os.MkdirAll(applications, 0o755); err != nil {
		return api.PathError(applications, err)
	}
	// Made beside where it goes, so it gets there in one move
	made, err := os.MkdirTemp(applications, ".dobase-")
	if err != nil {
		return api.PathError(applications, err)
	}
	defer os.RemoveAll(made)
	if err := unpack(archive, made); err != nil {
		return err
	}
	bundle := filepath.Join(made, "Electron.app")
	listPath := filepath.Join(bundle, "Contents", "Info.plist")
	list, err := os.ReadFile(listPath)
	if err != nil {
		return api.Failf("%s is not Electron for a Mac: it has no Electron.app.", archive)
	}

	resources := filepath.Join(bundle, "Contents", "Resources")
	a.Code = filepath.Join(resources, "app")
	if err := a.writeCode(); err != nil {
		return err
	}
	drawn, err := icns(picture)
	if err == nil {
		err = os.WriteFile(filepath.Join(resources, "app.icns"), drawn, 0o644)
	}
	if err != nil {
		return api.Failf("Could not make the app's icon: %v", err)
	}
	// Electron's own app and icon, which the app's replace
	os.Remove(filepath.Join(resources, "default_app.asar"))
	os.Remove(filepath.Join(resources, "electron.icns"))

	for key, value := range map[string]string{
		"CFBundleIdentifier":           bundleID,
		"CFBundleName":                 a.Name,
		"CFBundleDisplayName":          a.Name,
		"CFBundleIconFile":             "app.icns",
		"LSApplicationCategoryType":    "public.app-category.productivity",
		"NSCameraUsageDescription":     "For calls in a room.",
		"NSMicrophoneUsageDescription": "For calls in a room.",
		// The links `dobase --open` hands over
		"CFBundleURLTypes": "<array><dict><key>CFBundleURLName</key><string>" + EscapeHTML(a.Name) +
			"</string><key>CFBundleURLSchemes</key><array><string>web+dobase</string></array></dict></array>",
	} {
		list = plistSet(list, key, value)
	}
	if version := plistString("CFBundleShortVersionString", list); a.Electron == "" {
		a.Electron = version
	}
	if err := os.WriteFile(listPath, list, 0o644); err != nil {
		return api.PathError(listPath, err)
	}

	if err := os.RemoveAll(a.Path); err != nil {
		return api.PathError(a.Path, err)
	}
	if err := os.Rename(bundle, a.Path); err != nil {
		return api.PathError(a.Path, err)
	}
	a.Code = filepath.Join(a.Path, "Contents", "Resources", "app")
	a.Program = filepath.Join(a.Path, "Contents", "MacOS", "Electron")
	// Changed, so the signature it came with no longer holds. One made here
	// is enough for a program that was made here.
	if err := run("codesign", "--force", "--deep", "--sign", "-", a.Path); err != nil {
		return api.Failf("Could not sign %s: %v", a.Path, err)
	}
	return nil
}

// makeDesktopEntry makes the app one of a Linux desktop's: its scripts, its icon
// and an entry that starts Electron on them.
func (a *App) makeDesktopEntry(directory, archive string, icon []byte) error {
	// Without an Electron of the system's the app keeps one, and not when it has
	kept := filepath.Join(directory, "electron")
	if err := os.RemoveAll(kept); err != nil {
		return api.PathError(kept, err)
	}
	if archive != "" {
		if err := unpack(archive, kept); err != nil {
			return err
		}
		a.Program = filepath.Join(kept, "electron")
		if _, err := os.Stat(a.Program); err != nil {
			return api.Failf("%s is not Electron for Linux: it has no electron in it.", archive)
		}
		if version, err := os.ReadFile(filepath.Join(kept, "version")); err == nil && a.Electron == "" {
			a.Electron = strings.TrimSpace(string(version))
		}
	}
	a.Code = filepath.Join(directory, "shell")
	if err := a.writeCode(); err != nil {
		return err
	}

	a.Path = desktopEntry(directory)
	// A desktop entry's way of quoting what it starts
	quoted := func(path string) string {
		return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "`", "\\`", `$`, `\$`).Replace(path) + `"`
	}
	entry := "[Desktop Entry]\nType=Application\nName=" + a.Name + "\n" +
		"Exec=" + quoted(a.Program) + " " + quoted(a.Code) + " %U\n" +
		"Icon=dobase\nStartupWMClass=dobase\nCategories=Network;Office;\nMimeType=x-scheme-handler/web+dobase;\n"
	for path, contents := range map[string][]byte{a.Path: []byte(entry), desktopIcon(directory): icon} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return api.PathError(path, err)
		}
		if err := os.WriteFile(path, contents, 0o644); err != nil {
			return api.PathError(path, err)
		}
	}
	// So web+dobase:// links from elsewhere find it; a desktop without these goes without
	run("update-desktop-database", filepath.Dir(a.Path))
	run("xdg-mime", "default", filepath.Base(a.Path), "x-scheme-handler/web+dobase")
	return nil
}

// writeCode puts the app's scripts where Electron is started on them, with the
// server they are for.
func (a App) writeCode() error {
	if err := os.RemoveAll(a.Code); err != nil {
		return api.PathError(a.Code, err)
	}
	if err := os.MkdirAll(a.Code, 0o755); err != nil {
		return api.PathError(a.Code, err)
	}
	files := map[string][]byte{
		"package.json": []byte(api.Object("name", "dobase", "productName", a.Name, "version", "1.0.0", "main", "main.js").Pretty() + "\n"),
		"config.json":  []byte(api.Object("server", a.Server, "name", a.Name, "data", a.Data).Pretty() + "\n"),
	}
	scripts, _ := shell.ReadDir("shell")
	for _, script := range scripts {
		files[script.Name()], _ = shell.ReadFile("shell/" + script.Name())
	}
	for name, contents := range files {
		if err := os.WriteFile(filepath.Join(a.Code, name), contents, 0o644); err != nil {
			return api.PathError(filepath.Join(a.Code, name), err)
		}
	}
	return nil
}

// appIcon is the server's icon as the manifest has it: its biggest PNG that
// isn't only there to be cut to a shape.
func appIcon(manifestURL string, manifest api.Value) ([]byte, image.Image, error) {
	address, biggest := "", 0
	for _, icon := range manifest.Get("icons").Items() {
		size, _ := strconv.Atoi(strings.Split(icon.Get("sizes").S(), "x")[0])
		if icon.Get("type").S() == "image/png" && icon.Get("purpose").Or("any") != "maskable" && size > biggest {
			address, biggest = icon.Get("src").S(), size
		}
	}
	base, err := url.Parse(manifestURL)
	if err == nil && address != "" {
		base, err = base.Parse(address)
	}
	if err != nil || address == "" {
		return nil, nil, api.Failf("The manifest at %s names no PNG icon to give the app.", manifestURL)
	}
	contents, _, err := fetch(base.String())
	if err != nil {
		return nil, nil, err
	}
	picture, err := png.Decode(bytes.NewReader(contents))
	if err != nil {
		return nil, nil, api.Failf("The icon at %s is not a PNG: %v", base, err)
	}
	return contents, picture, nil
}

// isOurBundle says whether the app at path is one `dobase app install` made.
func isOurBundle(path string) bool {
	list, err := os.ReadFile(filepath.Join(path, "Contents", "Info.plist"))
	return err == nil && plistString("CFBundleIdentifier", list) == bundleID
}

// Where a desktop looks for a person's own programs and their icons: beside
// the app's directory.
func desktopEntry(directory string) string {
	return filepath.Join(filepath.Dir(directory), "applications", "dobase.desktop")
}

func desktopIcon(directory string) string {
	return filepath.Join(filepath.Dir(directory), "icons", "hicolor", "512x512", "apps", "dobase.png")
}

func (a App) save() error {
	directory, err := appDirectory()
	if err != nil {
		return err
	}
	record := api.Object("server", a.Server, "name", a.Name, "path", a.Path, "program", a.Program, "code", a.Code,
		"data", a.Data, "electron", a.Electron).Pretty()
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
	app := App{Server: record.Get("server").S(), Name: record.Get("name").Or("Dobase"), Path: record.Get("path").S(),
		Program: record.Get("program").S(), Code: record.Get("code").S(), Data: record.Get("data").S(), Electron: record.Get("electron").S()}
	if browser := record.Get("browser").S(); browser != "" {
		app.earlier = &browserApp{Browser: browser, Profile: record.Get("profile").S(), Manifest: record.Get("manifest").S()}
		return app, app.Server != "" && app.earlier.Profile != ""
	}
	return app, app.Server != "" && app.Program != "" && app.Code != "" && app.Data != ""
}

// appDirectory is where the app's sign-in and what is known about it are kept.
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
