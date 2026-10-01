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
	// Status is the HTTP status when the server turned the request down, else 0.
	Status int
}

func (e *Error) Error() string { return e.Message }

// Failf is an error that exits with 1.
func Failf(format string, args ...any) error {
	return &Error{Kind: Failed, Message: fmt.Sprintf(format, args...)}
}

// Usagef is a usage error, which exits with 2.
func Usagef(format string, args ...any) error {
	return &Error{Kind: Usage, Message: fmt.Sprintf(format, args...)}
}

// KindOf is the kind of any error: Failed unless it's an *Error saying otherwise.
func KindOf(err error) Kind {
	var e *Error
	if errors.As(err, &e) {
		return e.Kind
	}
	return Failed
}

// StatusOf is the HTTP status the server answered an error with, or 0.
func StatusOf(err error) int {
	var e *Error
	if errors.As(err, &e) {
		return e.Status
	}
	return 0
}
