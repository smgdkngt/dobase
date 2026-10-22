package config

import "os"

// lock is nothing on Windows: two processes that refresh at the same moment
// can end the login there, after which `dobase login` makes a new one.
func lock(*os.File) error { return nil }

func unlock(*os.File) {}
