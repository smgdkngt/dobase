//go:build !windows

package events

import (
	"os"
	"syscall"
)

// hold takes the file for this process alone, and says whether it got it. The
// system lets go of it when the process ends, however it ends.
func hold(file *os.File) bool {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) == nil
}
