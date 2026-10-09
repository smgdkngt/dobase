package events

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Bookmark is where a listener was: the number of the last event it printed.
// Each listener has one under its own name, so a Mac and a server each keep
// their place. It is kept in a file after every line.
type Bookmark struct {
	// Cursor is the number to ask after. Known is false for a listener that
	// never asked: it starts where the stream is now, not a week back.
	Cursor int64
	Known  bool

	path   string
	server string
	lock   *os.File
}

// Dir is where bookmarks are kept: the place for what a program remembers.
func Dir() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(base, "dobase", "events")
}

// ValidName says whether a listener can be called this: it becomes a file's name.
func ValidName(name string) bool {
	if name == "" || len(name) > 64 || strings.HasPrefix(name, ".") {
		return false
	}
	for _, char := range name {
		letter := ('a' <= char && char <= 'z') || ('A' <= char && char <= 'Z') || ('0' <= char && char <= '9')
		if !letter && char != '-' && char != '_' && char != '.' {
			return false
		}
	}
	return true
}

// OpenBookmark reads the bookmark of the listener called name, for this
// server, and holds it until Close: two listeners under one name would each
// print what the other already had.
func OpenBookmark(name, server string) (*Bookmark, error) {
	dir := Dir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, api.PathError(dir, err)
	}
	bookmark := &Bookmark{path: filepath.Join(dir, name+".json"), server: server}

	lock, err := os.OpenFile(filepath.Join(dir, name+".lock"), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return nil, api.PathError(dir, err)
	}
	if !hold(lock) {
		lock.Close()
		return nil, api.Failf("Another `dobase events --name %s` is listening already. Give this one a name of its own with --name.", name)
	}
	bookmark.lock = lock

	contents, err := os.ReadFile(bookmark.path)
	if err != nil {
		return bookmark, nil
	}
	// A bookmark from another server says nothing about this one's numbers
	if kept, err := api.Parse(contents); err == nil && kept.Get("server").S() == server && !kept.Get("cursor").IsNull() {
		bookmark.Cursor, bookmark.Known = kept.Get("cursor").Int(), true
	}
	return bookmark, nil
}

// Move sets the bookmark at cursor and keeps it. Written to a file beside it
// and renamed over it, so a listener stopped at any moment leaves a bookmark
// that is whole.
func (b *Bookmark) Move(cursor int64) error {
	if b.Known && cursor == b.Cursor {
		return nil
	}
	b.Cursor, b.Known = cursor, true
	if b.path == "" {
		return nil
	}

	beside := b.path + ".new"
	if err := os.WriteFile(beside, []byte(api.Object("server", b.server, "cursor", cursor).Pretty()+"\n"), 0o600); err != nil {
		return api.PathError(beside, err)
	}
	if err := os.Rename(beside, b.path); err != nil {
		return api.PathError(b.path, err)
	}
	return nil
}

// Close lets go of the bookmark, for another listener to take.
func (b *Bookmark) Close() {
	if b.lock != nil {
		b.lock.Close()
		b.lock = nil
	}
}
