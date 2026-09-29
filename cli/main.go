// Command dobase is a command-line client for the Dobase API. Run `dobase help` to get started.
package main

import (
	"os"

	"github.com/smgdkngt/dobase/cli/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], os.Stdout, os.Stderr))
}
