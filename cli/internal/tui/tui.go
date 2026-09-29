// Package tui is `dobase` without arguments in a terminal: a full-screen app
// to look around your tools, move cards, tick off todos and chat.
package tui

import (
	"github.com/smgdkngt/dobase/cli/internal/api"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// Run opens the app until it's quit.
func Run(cfg *config.Config, userAgent string) error {
	return api.Failf("not yet")
}
