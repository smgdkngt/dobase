package command

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// browserApp is the app as `dobase app install` first made it: a web app kept
// by a Chromium-family browser in a profile of its own. On a Mac the system
// took that browser for the one you browse with, so it is no longer made; what
// is left here takes one away.
type browserApp struct {
	Browser  string // the browser's program
	Profile  string // the profile only this app uses
	Manifest string // the app's identity to the browser
}

// remove takes the app out of its browser, which removes what the browser put
// on the system, and then deletes its profile.
func (b browserApp) remove(directory string) error {
	// A browser that is gone took its apps along
	session, err := openDevtools(b.Browser, "--user-data-dir="+b.Profile, "--no-first-run", "--no-default-browser-check", "--no-startup-window")
	if err == nil {
		_, err = session.call("PWA.uninstall", map[string]any{"manifestId": b.Manifest})
		session.close()
		if err == errBrowserLeft {
			// A second start on a profile in use hands over to the first one and leaves
			return api.Failf("%s left before it answered. If Dobase is open as an app, quit it and try again.", filepath.Base(b.Browser))
		}
	}
	// Only ever the directory this made
	if b.Profile == filepath.Join(directory, "app") {
		if err := os.RemoveAll(b.Profile); err != nil {
			return api.PathError(b.Profile, err)
		}
	}
	return nil
}

// How long the browser gets to answer, and to leave once told to.
const (
	browserWait = 90 * time.Second
	leaveWait   = 10 * time.Second
)

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
