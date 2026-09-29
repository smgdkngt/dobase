// Package config says where the CLI finds its server and token. DOBASE_URL and
// DOBASE_TOKEN override the saved config, which lives in ~/.config/dobase/config.json.
package config

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

type Config struct {
	saved  api.Value
	loaded bool
}

// Path is where the config is saved.
func Path() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "dobase", "config.json")
}

// URL is the server, without a trailing slash, or "".
func (c *Config) URL() string {
	url := os.Getenv("DOBASE_URL")
	if url == "" {
		url = c.load().Get("url").S()
	}
	return strings.TrimRight(url, "/")
}

// Token is the access token, or "".
func (c *Config) Token() string {
	if token := os.Getenv("DOBASE_TOKEN"); token != "" {
		return token
	}
	return c.load().Get("token").S()
}

// Save writes the URL and token to a file only this user can read.
func (c *Config) Save(url, token string) error {
	path := Path()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return api.PathError(dir, err)
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return api.PathError(dir, err)
	}
	contents := api.Object("url", strings.TrimRight(url, "/"), "token", token).Pretty()

	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return api.PathError(path, err)
	}
	defer file.Close()
	if err := os.Chmod(path, 0o600); err != nil {
		return api.PathError(path, err)
	}
	if _, err := file.WriteString(contents); err != nil {
		return api.PathError(path, err)
	}
	c.loaded = false
	return nil
}

// Forget deletes the saved config.
func (c *Config) Forget() error {
	path := Path()
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return api.PathError(path, err)
	}
	c.loaded = false
	return nil
}

func (c *Config) load() api.Value {
	if !c.loaded {
		c.saved = api.Null
		if contents, err := os.ReadFile(Path()); err == nil {
			if value, err := api.Parse(contents); err == nil {
				c.saved = value
			}
		}
		c.loaded = true
	}
	return c.saved
}
