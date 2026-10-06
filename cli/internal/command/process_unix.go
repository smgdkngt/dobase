//go:build !windows

package command

import (
	"os/exec"
	"syscall"
)

// detach gives a program a session of its own, so closing the terminal this
// ran in doesn't take it along.
func detach(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
}

// alive says whether there is a process with this id.
func alive(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}
