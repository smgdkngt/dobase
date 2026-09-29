package api

import (
	"errors"
	"fmt"
)

// Kind says how the CLI exits on an error.
type Kind int

const (
	// Failed is anything that went wrong: exits with 1.
	Failed Kind = iota
	// Usage is wrong arguments: exits with 2.
	Usage
	// Help is `--help` on a command: its usage, printed to stdout.
	Help
)

// Error is what commands and the client return.
type Error struct {
	Kind    Kind
	Message string
}

func (e *Error) Error() string { return e.Message }

// Failf is an error that exits with 1.
func Failf(format string, args ...any) error {
	return &Error{Failed, fmt.Sprintf(format, args...)}
}

// Usagef is a usage error, which exits with 2.
func Usagef(format string, args ...any) error {
	return &Error{Usage, fmt.Sprintf(format, args...)}
}

// KindOf is the kind of any error: Failed unless it's an *Error saying otherwise.
func KindOf(err error) Kind {
	var e *Error
	if errors.As(err, &e) {
		return e.Kind
	}
	return Failed
}
