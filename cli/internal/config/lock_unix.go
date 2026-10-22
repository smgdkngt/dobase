//go:build !windows

package config

import (
	"os"
	"syscall"
)

// lock waits until this process alone holds file; unlock lets go. The system
// lets go too when the process ends, however it ends.
func lock(file *os.File) error {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_EX)
}

func unlock(file *os.File) {
	syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
}
