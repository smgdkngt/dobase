package command

import (
	"archive/zip"
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// The browser of an app of the earlier kind is this test program started over:
// with DOBASE_TEST_BROWSER set it writes down how it was started and what it is
// told over the debugging pipe, and leaves at once when DOBASE_TEST_BROWSER_SAYS
// says so.
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
	if says == "leaves" {
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
		// Something nobody asked about comes first, as a browser's events do
		reply := api.Object("id", call.Get("id"), "result", map[string]any{})
		out.WriteString(`{"method":"Target.targetCreated","params":{}}` + "\x00" + reply.JSON() + "\x00")
		if method == "Browser.close" {
			return
		}
	}
}

// packed is a file in a zip; a link when it leads somewhere.
type packed struct {
	name, contents, link string
	runs                 bool
}

func zipOf(t *testing.T, files ...packed) []byte {
	t.Helper()
	var archive bytes.Buffer
	writer := zip.NewWriter(&archive)
	for _, file := range files {
		header := &zip.FileHeader{Name: file.name, Method: zip.Deflate}
		contents := file.contents
		switch {
		case file.link != "":
			header.SetMode(os.ModeSymlink | 0o755)
			contents = file.link
		case file.runs:
			header.SetMode(0o755)
		default:
			header.SetMode(0o644)
		}
		entry, err := writer.CreateHeader(header)
		if err != nil {
			t.Fatal(err)
		}
		entry.Write([]byte(contents))
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return archive.Bytes()
}

const electronList = `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Electron</string>
	<key>CFBundleIconFile</key>
	<string>electron.icns</string>
	<key>CFBundleIdentifier</key>
	<string>com.github.Electron</string>
	<key>CFBundleName</key>
	<string>Electron</string>
	<key>CFBundleShortVersionString</key>
	<string>VERSION</string>
	<key>NSCameraUsageDescription</key>
	<string>This app needs access to the camera</string>
</dict>
</plist>
`

// Electron as its releases pack it: an app bundle for a Mac, a directory with
// the program in it for Linux.
func macElectron(t *testing.T, version string) []byte {
	framework := "Electron.app/Contents/Frameworks/Electron Framework.framework/"
	return zipOf(t,
		packed{name: "LICENSE", contents: "MIT"},
		packed{name: "Electron.app/Contents/Info.plist", contents: strings.Replace(electronList, "VERSION", version, 1)},
		packed{name: "Electron.app/Contents/MacOS/Electron", contents: "the program", runs: true},
		packed{name: "Electron.app/Contents/Resources/default_app.asar", contents: "Electron's own app"},
		packed{name: "Electron.app/Contents/Resources/electron.icns", contents: "Electron's own icon"},
		packed{name: framework + "Versions/A/Electron Framework", contents: "the browser", runs: true},
		packed{name: framework + "Electron Framework", link: "Versions/A/Electron Framework"},
	)
}

func linuxElectron(t *testing.T, version string) []byte {
	return zipOf(t, packed{name: "electron", contents: "the program", runs: true}, packed{name: "version", contents: version + "\n"})
}

// fakeElectron makes Electron's releases a server here that has version as its
// newest, with one zip per system, and this machine one with the given chip.
func fakeElectron(t *testing.T, version, chip string) *int {
	t.Helper()
	files := map[string][]byte{
		"electron-v" + version + "-darwin-arm64.zip": macElectron(t, version),
		"electron-v" + version + "-linux-x64.zip":    linuxElectron(t, version),
	}
	sums := ""
	for name, contents := range files {
		sum := sha256.Sum256(contents)
		sums += hex.EncodeToString(sum[:]) + " *" + name + "\n"
	}
	downloads := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(r.URL.Path, "/download/v"+version+"/")
		switch {
		case r.URL.Path == "/latest":
			http.Redirect(w, r, "/tag/v"+version, http.StatusFound)
		case name == "SHASUMS256.txt":
			w.Write([]byte(sums))
		case files[name] != nil:
			downloads++
			w.Write(files[name])
		default:
			http.NotFound(w, r)
		}
	}))
	oldReleases, oldChip, oldLook := electronReleases, goarch, lookPath
	t.Cleanup(func() {
		server.Close()
		electronReleases, goarch, lookPath = oldReleases, oldChip, oldLook
	})
	electronReleases, goarch = server.URL, chip
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	return &downloads
}

const manifest = `{"name": "Our Tools", "start_url": "/", "display": "standalone", "icons": [
	{"src": "/icon.svg", "type": "image/svg+xml", "sizes": "any"},
	{"src": "/icon-192.png", "type": "image/png", "sizes": "192x192"},
	{"src": "/icon-512.png", "type": "image/png", "sizes": "512x512"},
	{"src": "/cut-1024.png", "type": "image/png", "sizes": "1024x1024", "purpose": "maskable"}]}`

// blue is a picture of one colour, as a PNG.
func blue(t *testing.T, size int) []byte {
	t.Helper()
	picture := image.NewRGBA(image.Rect(0, 0, size, size))
	for i := 0; i < len(picture.Pix); i += 4 {
		copy(picture.Pix[i:], []byte{0, 113, 227, 255})
	}
	var drawn bytes.Buffer
	if err := png.Encode(&drawn, picture); err != nil {
		t.Fatal(err)
	}
	return drawn.Bytes()
}

// dobaseServer is a Dobase as far as installing it goes: its manifest and its icon.
func dobaseServer(t *testing.T, manifest string) string {
	t.Helper()
	return dobaseServerSaying(t, &manifest)
}

// dobaseServerSaying is one whose manifest can change while it runs.
func dobaseServerSaying(t *testing.T, manifest *string) string {
	t.Helper()
	icon := blue(t, 64)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/manifest.json":
			w.Write([]byte(*manifest))
		case "/icon-512.png":
			w.Write(icon)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)
	return server.URL
}

func read(t *testing.T, path ...string) string {
	t.Helper()
	contents, err := os.ReadFile(filepath.Join(path...))
	if err != nil {
		t.Fatal(err)
	}
	return string(contents)
}

func quiet(string) {}

func TestInstallAppMakesAMacAppOfElectronWithTheServersNameAndIcon(t *testing.T) {
	started := fakeSystem(t, "darwin", "codesign")
	fakeElectron(t, "44.6.0", "arm64")
	home, _ := homeDir()
	server := dobaseServer(t, manifest)
	var told []string

	app, err := InstallApp(server, "", func(line string) { told = append(told, line) })
	if err != nil {
		t.Fatal(err)
	}
	bundle := filepath.Join(home, "Applications", "Our Tools.app")
	data := filepath.Join(home, ".local", "share", "dobase", "data")
	want := App{Server: server, Name: "Our Tools", Path: bundle, Program: filepath.Join(bundle, "Contents", "MacOS", "Electron"),
		Code: filepath.Join(bundle, "Contents", "Resources", "app"), Data: data, Electron: "44.6.0"}
	if !reflect.DeepEqual(app, want) {
		t.Errorf("app %+v", app)
	}
	if !reflect.DeepEqual(told, []string{"Getting Electron 44.6.0, which the app runs in…"}) {
		t.Errorf("told %q", told)
	}

	// The system knows it by its own name, and hands it the links `--open` makes
	list := read(t, bundle, "Contents", "Info.plist")
	for _, has := range []string{
		"<key>CFBundleIdentifier</key>\n\t<string>co.dobase.app</string>",
		"<key>CFBundleName</key>\n\t<string>Our Tools</string>",
		"<key>CFBundleDisplayName</key>\n\t<string>Our Tools</string>",
		"<key>CFBundleIconFile</key>\n\t<string>app.icns</string>",
		"<key>NSCameraUsageDescription</key>\n\t<string>For calls in a room.</string>",
		"<key>CFBundleURLSchemes</key><array><string>web+dobase</string></array>",
		"<key>CFBundleShortVersionString</key>\n\t<string>44.6.0</string>",
	} {
		if !strings.Contains(list, has) {
			t.Errorf("Info.plist lacks %s:\n%s", has, list)
		}
	}
	if !strings.HasSuffix(strings.TrimSpace(list), "</dict>\n</plist>") {
		t.Errorf("Info.plist ends in %q", list[len(list)-40:])
	}

	// Electron as it came, with the app's scripts and icon in place of its own
	if info, err := os.Stat(app.Program); err != nil || info.Mode().Perm()&0o100 == 0 {
		t.Errorf("the program can't be run: %v", err)
	}
	framework := filepath.Join(bundle, "Contents", "Frameworks", "Electron Framework.framework", "Electron Framework")
	if link, err := os.Readlink(framework); err != nil || link != "Versions/A/Electron Framework" || read(t, framework) != "the browser" {
		t.Errorf("the framework's link: %q, %v", link, err)
	}
	resources := filepath.Join(bundle, "Contents", "Resources")
	for _, gone := range []string{"default_app.asar", "electron.icns"} {
		if _, err := os.Stat(filepath.Join(resources, gone)); !os.IsNotExist(err) {
			t.Errorf("%s is still there", gone)
		}
	}
	if icon := read(t, resources, "app.icns"); !strings.HasPrefix(icon, "icns") {
		t.Errorf("the icon starts with %q", icon[:4])
	}
	main, _ := shell.ReadFile("shell/main.js")
	if read(t, app.Code, "main.js") != string(main) || read(t, app.Code, "links.js") == "" || read(t, app.Code, "preload.js") == "" {
		t.Error("the app's scripts are not the ones this was built with")
	}
	config := api.MustParse(read(t, app.Code, "config.json"))
	if config.Get("server").S() != server || config.Get("name").S() != "Our Tools" || config.Get("data").S() != data {
		t.Errorf("config %s", config.JSON())
	}
	if pack := api.MustParse(read(t, app.Code, "package.json")); pack.Get("main").S() != "main.js" {
		t.Errorf("package %s", pack.JSON())
	}

	// Signed here once everything is in it, and nothing left lying around
	if want := []string{"codesign --force --deep --sign - " + bundle}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}
	left, _ := filepath.Glob(filepath.Join(home, "Applications", ".dobase-*"))
	zips, _ := filepath.Glob(filepath.Join(home, ".local", "share", "dobase", "*.zip"))
	if len(left)+len(zips) > 0 {
		t.Errorf("left behind: %q %q", left, zips)
	}

	kept, found := InstalledApp(server + "/")
	if !found || !reflect.DeepEqual(kept, app) {
		t.Errorf("kept %+v, %v", kept, found)
	}
	if _, found := InstalledApp("https://elsewhere.test"); found {
		t.Error("the app counts for another server too")
	}
	if _, err := InstallApp("https://elsewhere.test", "", quiet); err == nil || !strings.Contains(err.Error(), "dobase app remove") {
		t.Errorf("a second server: %v", err)
	}
}

func TestInstallAppAgainBringsTheAppUpToDateAndKeepsItsSignIn(t *testing.T) {
	fakeSystem(t, "darwin", "codesign")
	fakeElectron(t, "44.6.0", "arm64")
	says := manifest
	server := dobaseServerSaying(t, &says)
	app, err := InstallApp(server, "", quiet)
	if err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(app.Data, "Cookies"), []byte("signed in"), 0o600)
	os.WriteFile(filepath.Join(app.Code, "main.js"), []byte("an older script"), 0o644)

	// While it is open it is left alone
	appRunning = func(data string) bool { return data == app.Data }
	if _, err := InstallApp(server, "", quiet); err == nil || !strings.Contains(err.Error(), "Our Tools is open. Quit it") {
		t.Errorf("while it runs: %v", err)
	}
	if read(t, app.Code, "main.js") != "an older script" {
		t.Error("it was changed all the same")
	}

	appRunning = func(string) bool { return false }
	fakeElectron(t, "45.0.1", "arm64")
	again, err := InstallApp(server, "", quiet)
	if err != nil {
		t.Fatal(err)
	}
	if again.Electron != "45.0.1" || again.Path != app.Path || read(t, app.Code, "main.js") == "an older script" {
		t.Errorf("again %+v", again)
	}
	if !strings.Contains(read(t, app.Path, "Contents", "Info.plist"), "<string>45.0.1</string>") {
		t.Error("the bundle is still the old Electron")
	}
	if read(t, app.Data, "Cookies") != "signed in" {
		t.Error("the sign-in went")
	}

	// A server that took another name is the app under that name, and only that one
	says = strings.Replace(manifest, "Our Tools", "Tools: Ours", 1)
	renamed, err := InstallApp(server, "", quiet)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(renamed.Path) != "Tools- Ours.app" || renamed.Name != "Tools: Ours" {
		t.Errorf("renamed %+v", renamed)
	}
	if _, err := os.Stat(app.Path); !os.IsNotExist(err) {
		t.Errorf("the app under the old name is still there: %v", err)
	}
}

func TestInstallAppLeavesAnotherAppOfThatNameAlone(t *testing.T) {
	fakeSystem(t, "darwin", "codesign")
	fakeElectron(t, "44.6.0", "arm64")
	home, _ := homeDir()
	other := filepath.Join(home, "Applications", "Our Tools.app", "Contents")
	os.MkdirAll(other, 0o755)
	os.WriteFile(filepath.Join(other, "Info.plist"), []byte("<key>CFBundleIdentifier</key><string>com.apple.Safari.WebApp.1234</string>"), 0o644)
	server := dobaseServer(t, manifest)

	if _, err := InstallApp(server, "", quiet); err == nil || !strings.Contains(err.Error(), "is another app") {
		t.Errorf("over another app: %v", err)
	}
	if !strings.Contains(read(t, other, "Info.plist"), "Safari") {
		t.Error("the other app was replaced")
	}
	if _, found := InstalledApp(server); found {
		t.Error("an app is kept all the same")
	}
}

func TestInstallAppTakesOnlyTheElectronItsReleaseLists(t *testing.T) {
	fakeSystem(t, "darwin", "codesign")
	fakeElectron(t, "44.6.0", "arm64")
	home, _ := homeDir()
	server := dobaseServer(t, manifest)

	// Another file than the one the checksums are of
	releases := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/latest":
			http.Redirect(w, r, "/tag/v44.6.0", http.StatusFound)
		case strings.HasSuffix(r.URL.Path, "SHASUMS256.txt"):
			w.Write([]byte(strings.Repeat("0", 64) + " *electron-v44.6.0-darwin-arm64.zip\n"))
		default:
			w.Write(macElectron(t, "44.6.0"))
		}
	}))
	defer releases.Close()
	electronReleases = releases.URL
	if _, err := InstallApp(server, "", quiet); err == nil || !strings.Contains(err.Error(), "not the file its release lists") {
		t.Errorf("a file that isn't the listed one: %v", err)
	}
	if left, _ := filepath.Glob(filepath.Join(home, ".local", "share", "dobase", "*.zip")); len(left) > 0 {
		t.Errorf("the file was kept: %q", left)
	}
	if _, err := os.Stat(filepath.Join(home, "Applications", "Our Tools.app")); !os.IsNotExist(err) {
		t.Errorf("an app was made of it: %v", err)
	}

	goarch = "riscv64"
	if _, err := InstallApp(server, "", quiet); err == nil || !strings.Contains(err.Error(), "no build for riscv64") {
		t.Errorf("a chip Electron isn't made for: %v", err)
	}
	goarch = "arm64"
	electronReleases = releases.URL + "/nowhere"
	if _, err := InstallApp(server, "", quiet); err == nil || !strings.Contains(err.Error(), "Could not tell the newest Electron") {
		t.Errorf("no newest release: %v", err)
	}
}

func TestOnLinuxTheAppRunsInTheSystemsElectron(t *testing.T) {
	started := fakeSystem(t, "linux", "/usr/bin/electron")
	downloads := fakeElectron(t, "44.6.0", "amd64")
	lookPath = func(name string) (string, error) { return "/usr/bin/" + name, nil }
	home, _ := homeDir()
	share := filepath.Join(home, ".local", "share")
	server := dobaseServer(t, manifest)

	app, err := InstallApp(server, "", quiet)
	if err != nil {
		t.Fatal(err)
	}
	want := App{Server: server, Name: "Our Tools", Path: filepath.Join(share, "applications", "dobase.desktop"), Program: "/usr/bin/electron",
		Code: filepath.Join(share, "dobase", "shell"), Data: filepath.Join(share, "dobase", "data")}
	if !reflect.DeepEqual(app, want) || *downloads != 0 {
		t.Errorf("app %+v after %d downloads", app, *downloads)
	}
	entry := read(t, app.Path)
	for _, has := range []string{"Name=Our Tools\n", `Exec="/usr/bin/electron" "` + app.Code + `" %U` + "\n", "Icon=dobase\n", "MimeType=x-scheme-handler/web+dobase;\n"} {
		if !strings.Contains(entry, has) {
			t.Errorf("the desktop entry lacks %q:\n%s", has, entry)
		}
	}
	if icon := read(t, share, "icons", "hicolor", "512x512", "apps", "dobase.png"); icon != string(blue(t, 64)) {
		t.Error("the icon is not the server's")
	}
	if read(t, app.Code, "main.js") == "" || api.MustParse(read(t, app.Code, "config.json")).Get("server").S() != server {
		t.Error("the app's scripts are not in place")
	}

	*started = nil
	if err := Open(server, server+"/tools/4/mail/drafts/9"); err != nil {
		t.Fatal(err)
	}
	if want := []string{"/usr/bin/electron " + app.Code + " " + server + "/tools/4/mail/drafts/9"}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}
	*started = nil
	if err := app.Show(""); err != nil || !reflect.DeepEqual(*started, []string{"/usr/bin/electron " + app.Code}) {
		t.Errorf("without a link it started %q, %v", *started, err)
	}

	// Another server's pages are not the app's
	*started = nil
	if err := Open(server, "https://example.com/tools/8"); err == nil || len(*started) != 1 || (*started)[0] != "xdg-open https://example.com/tools/8" {
		t.Errorf("elsewhere: started %q, %v", *started, err)
	}
}

func TestOnLinuxWithoutAnElectronTheAppKeepsOneOfItsOwn(t *testing.T) {
	fakeSystem(t, "linux")
	downloads := fakeElectron(t, "44.6.0", "amd64")
	home, _ := homeDir()
	server := dobaseServer(t, manifest)

	app, err := InstallApp(server, "", quiet)
	if err != nil {
		t.Fatal(err)
	}
	program := filepath.Join(home, ".local", "share", "dobase", "electron", "electron")
	if app.Program != program || app.Electron != "44.6.0" || *downloads != 1 {
		t.Errorf("app %+v after %d downloads", app, *downloads)
	}
	if info, err := os.Stat(program); err != nil || info.Mode().Perm()&0o100 == 0 {
		t.Errorf("its Electron can't be run: %v", err)
	}

	// An Electron of your own: its zip, or its program
	mine := filepath.Join(t.TempDir(), "electron-v43.0.0-linux-x64.zip")
	os.WriteFile(mine, linuxElectron(t, "43.0.0"), 0o644)
	if app, err = InstallApp(server, mine, quiet); err != nil || app.Electron != "43.0.0" || *downloads != 1 {
		t.Errorf("from a zip: %+v, %v, %d downloads", app, err, *downloads)
	}
	if _, err := os.Stat(mine); err != nil {
		t.Errorf("your zip went: %v", err)
	}
	lookPath = func(name string) (string, error) { return name, nil }
	if app, err = InstallApp(server, "/opt/electron/electron", quiet); err != nil || app.Program != "/opt/electron/electron" || app.Electron != "" {
		t.Errorf("from a program: %+v, %v", app, err)
	}
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	if _, err := InstallApp(server, "netscape", quiet); err == nil || !strings.Contains(err.Error(), `No Electron at "netscape"`) {
		t.Errorf("an Electron that isn't here: %v", err)
	}
	if _, err := InstallApp(server, mine+".tar", quiet); err == nil {
		t.Error("something that is neither")
	}
}

func TestInstallAppNeedsAServerThatIsADobase(t *testing.T) {
	started := fakeSystem(t, "darwin", "codesign")
	downloads := fakeElectron(t, "44.6.0", "arm64")

	if _, err := InstallApp(dobaseServer(t, "<html>"), "", quiet); err == nil || !strings.Contains(err.Error(), "not a web app manifest") {
		t.Errorf("no manifest: %v", err)
	}
	if _, err := InstallApp(dobaseServer(t, `{"name": "Bare"}`), "", quiet); err == nil || !strings.Contains(err.Error(), "names no PNG icon") {
		t.Errorf("no icon: %v", err)
	}
	if _, err := InstallApp(dobaseServer(t, manifest), "/opt/electron", quiet); err == nil || !strings.Contains(err.Error(), "takes Electron's zip") {
		t.Errorf("a program on a Mac: %v", err)
	}
	goos = "windows"
	if _, err := InstallApp(dobaseServer(t, manifest), "", quiet); err == nil || !strings.Contains(err.Error(), "macOS and Linux") {
		t.Errorf("windows: %v", err)
	}
	if len(*started) > 0 || *downloads > 0 {
		t.Errorf("started %q after %d downloads", *started, *downloads)
	}
}

// installedApp is an app as InstallApp leaves it on a Mac.
func installedApp(t *testing.T, server string) App {
	t.Helper()
	home, _ := homeDir()
	bundle := filepath.Join(home, "Applications", "Dobase.app")
	app := App{Server: server, Name: "Dobase", Path: bundle, Program: filepath.Join(bundle, "Contents", "MacOS", "Electron"),
		Code: filepath.Join(bundle, "Contents", "Resources", "app"), Data: filepath.Join(home, ".local", "share", "dobase", "data"), Electron: "44.6.0"}
	for _, directory := range []string{app.Code, app.Data} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	list := "<plist><dict><key>CFBundleIdentifier</key>\n<string>" + bundleID + "</string></dict></plist>"
	if err := os.WriteFile(filepath.Join(bundle, "Contents", "Info.plist"), []byte(list), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := app.save(); err != nil {
		t.Fatal(err)
	}
	return app
}

func TestOnAMacTheSystemHandsTheAppItsLinks(t *testing.T) {
	started := fakeSystem(t, "darwin", "open -a")
	app := installedApp(t, "https://dobase.test")

	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	if want := []string{"open -a " + app.Path + " web+dobase://" + strings.TrimPrefix(draft, "https://dobase.test/")}; !reflect.DeepEqual(*started, want) {
		t.Errorf("started %q", *started)
	}

	*started = nil
	if err := app.Show(""); err != nil || !reflect.DeepEqual(*started, []string{"open -a " + app.Path}) {
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
	started := fakeSystem(t, "darwin", "open https:")
	installedApp(t, "https://dobase.test")

	if err := Open("https://dobase.test", draft); err != nil {
		t.Fatal(err)
	}
	if last := (*started)[len(*started)-1]; len(*started) < 2 || !strings.HasPrefix((*started)[0], "open -a ") || last != "open "+draft {
		t.Errorf("started %q", *started)
	}
}

func TestAppRunningReadsTheAppsLock(t *testing.T) {
	data := t.TempDir()
	if appRunning(data) {
		t.Error("an app without a lock counts as open")
	}
	for target, want := range map[string]bool{"a-mac.local-" + itoa(os.Getpid()): true, "a-mac.local-0x": false, "nonsense": false} {
		lock := filepath.Join(data, "SingletonLock")
		os.Remove(lock)
		if err := os.Symlink(target, lock); err != nil {
			t.Skip("no symlinks here")
		}
		if got := appRunning(data); got != want {
			t.Errorf("%s: %v", target, got)
		}
	}
}

func TestRemoveTakesTheAppOffTheSystemWithItsSignIn(t *testing.T) {
	fakeSystem(t, "darwin")
	app := installedApp(t, "https://dobase.test")
	os.WriteFile(filepath.Join(app.Data, "Cookies"), []byte("signed in"), 0o600)

	// While it is open it is left alone
	appRunning = func(data string) bool { return data == app.Data }
	if err := app.Remove(); err == nil || !strings.Contains(err.Error(), "Dobase is open. Quit it") {
		t.Errorf("while it runs: %v", err)
	}
	if _, err := os.Stat(app.Path); err != nil {
		t.Errorf("it went all the same: %v", err)
	}

	appRunning = func(string) bool { return false }
	if err := app.Remove(); err != nil {
		t.Fatal(err)
	}
	for _, gone := range []string{app.Path, app.Data} {
		if _, err := os.Stat(gone); !os.IsNotExist(err) {
			t.Errorf("%s is still there: %v", gone, err)
		}
	}
	if _, found := InstalledApp("https://dobase.test"); found {
		t.Error("it is still kept")
	}

	// An app that took its place since is not this one's to remove
	app = installedApp(t, "https://dobase.test")
	os.WriteFile(filepath.Join(app.Path, "Contents", "Info.plist"), []byte("<key>CFBundleIdentifier</key><string>com.apple.Safari.WebApp.1234</string>"), 0o644)
	if err := app.Remove(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(app.Path); err != nil {
		t.Errorf("another app went: %v", err)
	}
}

func TestOnLinuxRemoveTakesTheEntryTheIconAndTheScripts(t *testing.T) {
	fakeSystem(t, "linux")
	fakeElectron(t, "44.6.0", "amd64")
	home, _ := homeDir()
	app, err := InstallApp(dobaseServer(t, manifest), "", quiet)
	if err != nil {
		t.Fatal(err)
	}

	if err := app.Remove(); err != nil {
		t.Fatal(err)
	}
	share := filepath.Join(home, ".local", "share")
	for _, gone := range []string{app.Path, app.Code, app.Data, filepath.Join(share, "dobase", "electron"), filepath.Join(share, "dobase", "app.json"),
		filepath.Join(share, "icons", "hicolor", "512x512", "apps", "dobase.png")} {
		if _, err := os.Stat(gone); !os.IsNotExist(err) {
			t.Errorf("%s is still there: %v", gone, err)
		}
	}
}

// An app of the earlier kind, as `dobase app install` left one before.
func earlierApp(t *testing.T, browser string) (App, string) {
	t.Helper()
	home, _ := homeDir()
	directory := filepath.Join(home, ".local", "share", "dobase")
	profile := filepath.Join(directory, "app")
	if err := os.MkdirAll(profile, 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(profile, "Cookies"), []byte("signed in"), 0o600)
	record := api.Object("server", "https://dobase.test", "name", "Dobase", "browser", browser, "profile", profile,
		"manifest", "https://dobase.test/", "id", "fapenbnbeacoicjbbcdidmbgdjlgdfij").Pretty()
	os.WriteFile(filepath.Join(directory, "app.json"), []byte(record), 0o600)
	app, found := InstalledApp("https://dobase.test")
	if !found {
		t.Fatal("the earlier app is not found")
	}
	return app, profile
}

func TestAnAppOfTheEarlierKindCanOnlyBeRemoved(t *testing.T) {
	started := fakeSystem(t, "darwin", "open https:")
	downloads := fakeElectron(t, "44.6.0", "arm64")
	log := filepath.Join(t.TempDir(), "browser.log")
	t.Setenv("DOBASE_TEST_BROWSER", log)
	t.Setenv("DOBASE_TEST_BROWSER_SAYS", "leaves")
	app, profile := earlierApp(t, os.Args[0])

	if _, err := InstallApp("https://dobase.test", "", quiet); err == nil || !strings.Contains(err.Error(), "the earlier way") || *downloads != 0 {
		t.Errorf("a new one beside it: %v, %d downloads", err, *downloads)
	}
	if err := app.Show(""); err == nil || !strings.Contains(err.Error(), "dobase app remove") {
		t.Errorf("opening it: %v", err)
	}
	// A link goes on to what else can open it
	if err := Open("https://dobase.test", draft); err != nil || (*started)[len(*started)-1] != "open "+draft {
		t.Errorf("a link: started %q, %v", *started, err)
	}

	// A profile in use is left alone
	if err := app.Remove(); err == nil || !strings.Contains(err.Error(), "quit it") {
		t.Errorf("while it runs: %v", err)
	}
	if _, err := os.Stat(profile); err != nil {
		t.Errorf("its profile went all the same: %v", err)
	}

	os.Remove(log)
	t.Setenv("DOBASE_TEST_BROWSER_SAYS", "")
	if err := app.Remove(); err != nil {
		t.Fatal(err)
	}
	told := strings.Split(strings.TrimSpace(read(t, log)), "\n")
	want := []string{
		"started --user-data-dir=" + profile + " --no-first-run --no-default-browser-check --no-startup-window --remote-debugging-pipe",
		`PWA.uninstall {"manifestId":"https://dobase.test/"}`,
		"Browser.close null",
	}
	if !reflect.DeepEqual(told, want) {
		t.Errorf("the browser was told\n%s", strings.Join(told, "\n"))
	}
	if _, found := InstalledApp("https://dobase.test"); found {
		t.Error("it is still kept")
	}
	if _, err := os.Stat(profile); !os.IsNotExist(err) {
		t.Errorf("its profile is still there: %v", err)
	}
}

func TestUnpackRefusesWhatWouldLandOutside(t *testing.T) {
	for name, files := range map[string][]packed{
		"a file":              {{name: "../outside", contents: "x"}},
		"a file from the top": {{name: "/outside", contents: "x"}},
		"a link out":          {{name: "link", link: "../../outside"}},
		"a link to anywhere":  {{name: "link", link: "/etc/passwd"}},
		// Each link stays inside as it is written, and together they lead out
		"links that add up": {{name: "deep/down/kept", contents: "x"}, {name: "deep/down/up", link: "../.."}, {name: "away", link: "deep/down/up/.."},
			{name: "away/outside", contents: "x"}},
	} {
		directory := t.TempDir()
		archive := filepath.Join(directory, "electron.zip")
		os.WriteFile(archive, zipOf(t, append([]packed{{name: "kept", contents: "x"}}, files...)...), 0o644)
		into := filepath.Join(directory, "into")
		if err := unpack(archive, into); err == nil || !strings.Contains(err.Error(), "outside it") {
			t.Errorf("%s: %v", name, err)
		}
		if _, err := os.Stat(filepath.Join(directory, "outside")); !os.IsNotExist(err) {
			t.Errorf("%s landed outside", name)
		}
	}
}

func TestAMacsIconIsThePictureWithRoomAroundIt(t *testing.T) {
	picture, _ := png.Decode(bytes.NewReader(blue(t, 512)))
	icon := macIcon(picture, 256)
	// 824 of 1024 across: 25 dots of room on each side of 256
	for point, want := range map[image.Point]color.RGBA{
		{0, 0}: {}, {24, 128}: {}, {128, 231}: {},
		{128, 128}: {0, 113, 227, 255}, {26, 26}: {0, 113, 227, 255}, {230, 128}: {0, 113, 227, 255},
	} {
		if got := icon.RGBAAt(point.X, point.Y); got != want {
			t.Errorf("at %v it is %v", point, got)
		}
	}
	// Where the edge falls inside a dot, the dot is that much of the colour (give
	// or take one: chips round a half differently)
	edge := macIcon(picture, 128).RGBAAt(12, 64)
	for at, want := range []int{0, 57, 114, 128} {
		if got := int([]uint8{edge.R, edge.G, edge.B, edge.A}[at]); got < want-1 || got > want+1 {
			t.Errorf("half a dot of it is %v", edge)
		}
	}

	file, err := icns(picture)
	if err != nil {
		t.Fatal(err)
	}
	if string(file[:4]) != "icns" || int(binary.BigEndian.Uint32(file[4:8])) != len(file) {
		t.Fatalf("the file starts with %q and says it is %d of %d long", file[:4], binary.BigEndian.Uint32(file[4:8]), len(file))
	}
	sizes := map[string]int{}
	for at := 8; at < len(file); {
		length := int(binary.BigEndian.Uint32(file[at+4 : at+8]))
		drawn, err := png.DecodeConfig(bytes.NewReader(file[at+8 : at+length]))
		if err != nil {
			t.Fatal(err)
		}
		sizes[string(file[at:at+4])] = drawn.Width
		at += length
	}
	if want := map[string]int{"ic11": 32, "ic12": 64, "ic07": 128, "ic08": 256, "ic13": 512, "ic09": 512}; !reflect.DeepEqual(sizes, want) {
		t.Errorf("sizes %v", sizes)
	}
}

func TestPlistSetReplacesAStringAndAddsWhatIsNew(t *testing.T) {
	list := []byte("<dict>\n\t<key>Name</key>\n\t<string>Electron</string>\n\t<key>Nested</key>\n\t<dict>\n\t</dict>\n</dict>\n")
	list = plistSet(list, "Name", "Tools & $1 <more>")
	list = plistSet(list, "Schemes", "<array><string>web+dobase</string></array>")
	want := "<dict>\n\t<key>Name</key>\n\t<string>Tools &amp; $1 &lt;more&gt;</string>\n\t<key>Nested</key>\n\t<dict>\n\t</dict>\n" +
		"\t<key>Schemes</key>\n\t<array><string>web+dobase</string></array>\n</dict>\n"
	if string(list) != want {
		t.Errorf("list\n%s", list)
	}
	if plistString("Name", list) != "Tools &amp; $1 &lt;more&gt;" || plistString("Nested", list) != "" {
		t.Errorf("read back %q", plistString("Name", list))
	}
}

func itoa(number int) string { return api.Of(number).JSON() }
