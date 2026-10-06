package command

import "os/exec"

// detach does nothing here: a program started on Windows already stays.
func detach(*exec.Cmd) {}

// alive is only asked about the app, which Windows doesn't have.
func alive(int) bool { return false }
