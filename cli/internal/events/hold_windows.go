package events

import "os"

// hold always gets the file: on Windows two listeners under one name are not told apart.
func hold(*os.File) bool { return true }
