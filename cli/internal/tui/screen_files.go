package tui

// Files: walk through the folders, look at a file, download it.

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/command"
)

var filesHints = []hint{{"↑↓", "choose"}, {"enter", "open"}, {"⌫", "up"}, {"d", "download"}, {"o", "browser"}, {"esc", "home"}}

var filesHelp = []hint{
	{"↑ ↓ / j k", "Choose a folder or file"},
	{"enter / →", "Open the folder, or show the file"},
	{"⌫ / ←", "Up one folder"},
	{"d", "Download the file into the folder you started dobase in"},
	{"o", "Open it in your browser"},
	{"r", "Reload"},
	{"esc", "Back home"},
}

type Files struct {
	notLive
	tool    api.Value
	listing api.Value
	// folder is the folder shown, or 0 for the top.
	folder   int64
	selected int
}

// fileEntry is a folder or a file in a listing.
type fileEntry struct {
	value  api.Value
	folder bool
}

func loadFiles(app *App, tool api.Value, folder int64) (*Files, error) {
	var params []api.Param
	if folder != 0 {
		params = append(params, api.Param{Name: "folder_id", Value: strconv.FormatInt(folder, 10)})
	}
	listing, err := app.get(toolPath(tool)+"/files", params...)
	if err != nil {
		return nil, err
	}
	return &Files{tool: tool, listing: listing, folder: folder}, nil
}

func (s *Files) Tool() (api.Value, bool) { return s.tool, true }
func (s *Files) Hints() []hint           { return filesHints }
func (s *Files) Help() []hint            { return filesHelp }

func (s *Files) entries() []fileEntry {
	var entries []fileEntry
	for _, folder := range s.listing.Get("folders").Items() {
		entries = append(entries, fileEntry{folder, true})
	}
	for _, file := range s.listing.Get("files").Items() {
		entries = append(entries, fileEntry{file, false})
	}
	return entries
}

func (s *Files) Refresh() Job {
	tool, folder, selected := s.tool, s.folder, s.selected
	return func(app *App) error {
		fresh, err := loadFiles(app, tool, folder)
		if err != nil {
			return err
		}
		fresh.selected = selected
		app.screen = fresh
		return nil
	}
}

func (s *Files) goTo(folder int64, fx *Fx) {
	tool := s.tool
	fx.job("Opening the folder", func(app *App) error {
		fresh, err := loadFiles(app, tool, folder)
		if err != nil {
			return err
		}
		app.screen = fresh
		return nil
	})
}

func (s *Files) Key(key Key, view *View, fx *Fx) bool {
	tool := s.tool.Get("id").Int()
	entries := s.entries()
	var entry *fileEntry
	if s.selected < len(entries) {
		entry = &entries[s.selected]
	}
	switch {
	case key.Code == KeyEnter || key.Code == KeyRight || key.Is('l'):
		switch {
		case entry == nil:
		case entry.folder:
			s.goTo(entry.value.Get("id").Int(), fx)
		default:
			fx.popup = fileDetail(entry.value)
		}
	case key.Code == KeyBackspace || key.Code == KeyLeft || key.Is('h'):
		if s.folder != 0 {
			parent, _ := strconv.ParseInt(s.listing.Get("folder", "parent_id").S(), 10, 64)
			s.goTo(parent, fx)
		}
	case key.Is('d'):
		if entry != nil && !entry.folder {
			id, name := entry.value.Get("id").Int(), entry.value.Get("name").S()
			destination := downloadPath(name)
			fx.popup = confirmPopup(fmt.Sprintf("Download “%s” to %s?", name, destination), "Downloading", func(app *App) error {
				if _, err := app.api.Download(fmt.Sprintf("/tools/%d/files/items/%d/download", tool, id), destination); err != nil {
					return err
				}
				app.say(fmt.Sprintf("Saved to %s 📥", destination), ToneSuccess)
				return nil
			})
		}
	case key.Is('o'):
		url := fmt.Sprintf("/tools/%d/files", tool)
		switch {
		case entry != nil && entry.folder:
			url = fmt.Sprintf("/tools/%d/files?folder_id=%s", tool, entry.value.Get("id").S())
		case s.folder != 0:
			url = fmt.Sprintf("/tools/%d/files?folder_id=%d", tool, s.folder)
		}
		fx.openURL = &url
	default:
		return moveSelection(&s.selected, len(entries), key)
	}
	return true
}

func (s *Files) Draw(b *Buffer, area Rect, view *View) {
	trail := []string{s.tool.Get("name").S()}
	for _, crumb := range s.listing.Get("breadcrumbs").Items() {
		trail = append(trail, crumb.Get("name").S())
	}
	if name := s.listing.Get("folder", "name"); !name.IsNull() {
		trail = append(trail, name.S())
	}
	block := panel(toolIcon("files")+" "+strings.Join(trail, " / "), true)

	entries := s.entries()
	if len(entries) == 0 {
		message := "No files yet. Drop some in with: dobase file upload"
		if s.folder != 0 {
			message = "This folder is empty. ⌫ to go up."
		}
		Paragraph{Lines: []Line{RawLine(message)}, Style: dim(), Block: block}.Render(b, area)
		return
	}
	width := sat(area.W - 34)
	items := make([]ListItem, len(entries))
	for i, entry := range entries {
		shared := ""
		if entry.value.Get("shared").Truthy() {
			shared = "  🔗"
		}
		name := entry.value.Get("name").S()
		if entry.folder {
			items[i] = Item(LineOf(
				Raw(" 📂 "),
				Styled(truncate(name, width), Style{}.With(Bold)),
				Styled(shared, dim())))
			continue
		}
		items[i] = Item(LineOf(
			Raw(" "+fileIcon(name)+" "),
			Raw(padded(truncate(name, width), width)),
			Styled(fmt.Sprintf("  %8s  %s", command.Bytes(entry.value.Get("file_size")), command.Day(entry.value.Get("created_at"))), dim()),
			Styled(shared, dim())))
	}
	s.selected = min(s.selected, len(items)-1)
	List{Items: items, Block: block, Highlight: selected()}.Render(b, area, s.selected)
}

func fileIcon(name string) string {
	extension := ""
	if index := strings.LastIndex(name, "."); index >= 0 {
		extension = strings.ToLower(name[index+1:])
	} else {
		extension = strings.ToLower(name)
	}
	switch extension {
	case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
		return "🎨"
	case "pdf":
		return "📕"
	case "mp4", "mov", "webm":
		return "🎬"
	case "mp3", "wav", "ogg", "m4a":
		return "🎵"
	case "zip", "gz", "tar":
		return "📦"
	case "xls", "xlsx", "csv", "numbers":
		return "📊"
	case "ppt", "pptx", "key":
		return "📈"
	}
	return "📄"
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return !errors.Is(err, fs.ErrNotExist)
}

// downloadPath is where a download goes: the current folder, without overwriting anything.
func downloadPath(name string) string {
	name = filepath.Base(name)
	if name == "." || name == "/" || name == ".." {
		name = "download"
	}
	if !exists(name) {
		return name
	}
	stem, extension := name, ""
	if index := strings.LastIndex(name, "."); index > 0 {
		stem, extension = name[:index], name[index:]
	}
	for number := 1; ; number++ {
		path := fmt.Sprintf("%s (%d)%s", stem, number, extension)
		if !exists(path) {
			return path
		}
	}
}

func fileDetail(file api.Value) *Detail {
	var lines []Line
	field(&lines, "Type", file.Get("content_type").S())
	field(&lines, "Size", command.Bytes(file.Get("file_size")))
	field(&lines, "Added", ago(file.Get("created_at"))+" by "+file.Get("creator", "name").S())
	if file.Get("shared").Truthy() {
		field(&lines, "Shared", "with a public link 🔗")
	}
	lines = append(lines, RawLine(""), StyledLine("Press esc, then d to download it here.", dim()))
	var url *string
	if value := file.Get("url"); !value.IsNull() {
		url = ptr(value.S())
	}
	return &Detail{title: file.Get("name").S(), lines: lines, url: url}
}
