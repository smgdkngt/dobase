package command

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Electron is what the app runs in: a Chromium nobody browses with, which shows
// the pages a script tells it to. Its releases are zips on GitHub, one per
// system, with a list of their checksums beside them.
var (
	electronReleases = "https://github.com/electron/electron/releases"
	goarch           = runtime.GOARCH
)

var electronVersion = regexp.MustCompile(`^\d+\.\d+\.\d+$`)

// latestElectron is the newest stable Electron: where the releases' "latest" leads.
func latestElectron() (string, error) {
	client := http.Client{Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Get(electronReleases + "/latest")
	if err != nil {
		return "", api.Failf("Could not reach %s: %v", electronReleases, err)
	}
	response.Body.Close()
	location := response.Header.Get("Location")
	version := strings.TrimPrefix(location[strings.LastIndex(location, "/")+1:], "v")
	if !electronVersion.MatchString(version) {
		return "", api.Failf("Could not tell the newest Electron from %s/latest (%s).", electronReleases, response.Status)
	}
	return version, nil
}

// fetchElectron downloads the newest Electron for this system into directory,
// checks it against the release's checksums, and returns the zip and its version.
func fetchElectron(directory string, tell func(string)) (string, string, error) {
	architecture, known := map[string]string{"arm64": "arm64", "amd64": "x64"}[goarch]
	if !known {
		return "", "", api.Failf("Electron has no build for %s. Point at one of your own with --electron.", goarch)
	}
	version, err := latestElectron()
	if err != nil {
		return "", "", err
	}
	name := fmt.Sprintf("electron-v%s-%s-%s.zip", version, goos, architecture)
	release := electronReleases + "/download/v" + version + "/"

	sums, _, err := fetch(release + "SHASUMS256.txt")
	if err != nil {
		return "", "", err
	}
	want := ""
	for _, line := range strings.Split(string(sums), "\n") {
		if fields := strings.Fields(line); len(fields) == 2 && strings.TrimPrefix(fields[1], "*") == name {
			want = fields[0]
		}
	}
	if want == "" {
		return "", "", api.Failf("Electron %s has no %s.", version, name)
	}

	tell(fmt.Sprintf("Getting Electron %s, which the app runs in…", version))
	response, err := http.Get(release + name)
	if err != nil {
		return "", "", api.Failf("Could not reach %s: %v", release+name, err)
	}
	defer response.Body.Close()
	if response.StatusCode >= 400 {
		return "", "", api.Failf("Could not read %s (%s).", release+name, response.Status)
	}
	archive := filepath.Join(directory, name)
	file, err := os.Create(archive)
	if err != nil {
		return "", "", api.PathError(archive, err)
	}
	sum := sha256.New()
	_, err = io.Copy(io.MultiWriter(file, sum), response.Body)
	if closed := file.Close(); err == nil {
		err = closed
	}
	if err == nil && hex.EncodeToString(sum.Sum(nil)) != want {
		err = fmt.Errorf("it is not the file its release lists")
	}
	if err != nil {
		os.Remove(archive)
		return "", "", api.Failf("Could not get %s: %v", release+name, err)
	}
	return archive, version, nil
}

// unpack puts what is in a zip into a directory, with its links and with what
// may be run still marked so.
func unpack(archive, into string) error {
	reader, err := zip.OpenReader(archive)
	if err != nil {
		return api.Failf("%s is not a zip: %v", archive, err)
	}
	defer reader.Close()

	inside := func(path string) bool {
		rel, err := filepath.Rel(into, path)
		return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
	}
	for _, packed := range reader.File {
		target := filepath.Join(into, packed.Name)
		if !inside(target) {
			return api.Failf("%s has a file that would land outside it: %s", archive, packed.Name)
		}
		mode := packed.Mode()
		if mode.IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return api.PathError(target, err)
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return api.PathError(target, err)
		}
		contents, err := packed.Open()
		if err != nil {
			return api.Failf("%s: %v", archive, err)
		}
		if mode&os.ModeSymlink != 0 {
			link, err := io.ReadAll(io.LimitReader(contents, 4096))
			contents.Close()
			if err != nil || filepath.IsAbs(string(link)) || !inside(filepath.Join(filepath.Dir(target), string(link))) {
				return api.Failf("%s has a link that leads outside it: %s", archive, packed.Name)
			}
			if err := os.Symlink(string(link), target); err != nil {
				return api.PathError(target, err)
			}
			continue
		}
		file, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode.Perm()|0o600)
		if err == nil {
			_, err = io.Copy(file, contents)
			if closed := file.Close(); err == nil {
				err = closed
			}
		}
		contents.Close()
		if err != nil {
			return api.PathError(target, err)
		}
	}
	return nil
}

// -- A Mac's app bundle -----------------------------------------------------------

// plistString is the string an Info.plist has for a key; "" when it has none.
func plistString(key string, list []byte) string {
	found := regexp.MustCompile(`<key>` + regexp.QuoteMeta(key) + `</key>\s*<string>([^<]*)</string>`).FindSubmatch(list)
	if found == nil {
		return ""
	}
	return string(found[1])
}

// plistSet gives a key of an Info.plist a value: a string, or a piece of plist
// when the value starts with a tag.
func plistSet(list []byte, key, value string) []byte {
	if !strings.HasPrefix(value, "<") {
		value = "<string>" + EscapeHTML(value) + "</string>"
	}
	had := regexp.MustCompile(`(<key>` + regexp.QuoteMeta(key) + `</key>\s*)<string>[^<]*</string>`)
	if had.Match(list) {
		return had.ReplaceAll(list, []byte("${1}"+strings.ReplaceAll(value, "$", "$$")))
	}
	end := bytes.LastIndex(list, []byte("</dict>"))
	if end < 0 {
		return list
	}
	added := "\t<key>" + key + "</key>\n\t" + value + "\n"
	return append(list[:end:end], append([]byte(added), list[end:]...)...)
}

// macIcon draws a picture the way a Mac's icons are drawn: on a square with
// room around it, so it is the size of the icons beside it.
func macIcon(picture image.Image, size int) *image.RGBA {
	icon := image.NewRGBA(image.Rect(0, 0, size, size))
	from := picture.Bounds()
	// Apple's grid: 824 of 1024 across
	body := float64(size) * 824 / 1024
	margin := (float64(size) - body) / 2
	scaleX, scaleY := float64(from.Dx())/body, float64(from.Dy())/body

	for y := 0; y < size; y++ {
		top, bottom := (float64(y)-margin)*scaleY, (float64(y)+1-margin)*scaleY
		for x := 0; x < size; x++ {
			left, right := (float64(x)-margin)*scaleX, (float64(x)+1-margin)*scaleX
			// The part of the picture this dot covers, each of its dots by how much of it
			var r, g, b, a float64
			for sy := max(int(top), 0); sy < from.Dy() && float64(sy) < bottom; sy++ {
				high := min(bottom, float64(sy)+1) - max(top, float64(sy))
				for sx := max(int(left), 0); sx < from.Dx() && float64(sx) < right; sx++ {
					part := high * (min(right, float64(sx)+1) - max(left, float64(sx)))
					if part <= 0 {
						continue
					}
					pr, pg, pb, pa := picture.At(from.Min.X+sx, from.Min.Y+sy).RGBA()
					r, g, b, a = r+float64(pr)*part, g+float64(pg)*part, b+float64(pb)*part, a+float64(pa)*part
				}
			}
			area := (right - left) * (bottom - top) * 257
			icon.SetRGBA(x, y, color.RGBA{R: uint8(r/area + 0.5), G: uint8(g/area + 0.5), B: uint8(b/area + 0.5), A: uint8(a/area + 0.5)})
		}
	}
	return icon
}

// icns is a Mac's icon file: the picture at the sizes the system asks for, each
// a PNG under the name of its size.
func icns(picture image.Image) ([]byte, error) {
	var entries bytes.Buffer
	for _, entry := range []struct {
		name string
		size int
	}{{"ic11", 32}, {"ic12", 64}, {"ic07", 128}, {"ic08", 256}, {"ic13", 512}, {"ic09", 512}} {
		var drawn bytes.Buffer
		if err := png.Encode(&drawn, macIcon(picture, entry.size)); err != nil {
			return nil, err
		}
		entries.WriteString(entry.name)
		binary.Write(&entries, binary.BigEndian, uint32(drawn.Len()+8))
		entries.Write(drawn.Bytes())
	}
	var file bytes.Buffer
	file.WriteString("icns")
	binary.Write(&file, binary.BigEndian, uint32(entries.Len()+8))
	file.Write(entries.Bytes())
	return file.Bytes(), nil
}
