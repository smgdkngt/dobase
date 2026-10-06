package cli

import (
	"bytes"
	"strings"
	"testing"

	"github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

func TestTheAppCommandsSayWhatIsMissing(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	var out bytes.Buffer
	ctx := command.NewCtx(&config.Config{}, &out, false, "test")

	t.Setenv("DOBASE_URL", "")
	if err := invoke(ctx, "app install"); err == nil || !strings.Contains(err.Error(), "dobase login") {
		t.Errorf("without a server: %v", err)
	}

	t.Setenv("DOBASE_URL", "https://dobase.test/")
	for _, name := range []string{"app open", "app remove"} {
		if err := invoke(ctx, name); err == nil || !strings.Contains(err.Error(), "No app for https://dobase.test here") {
			t.Errorf("%s without an app: %v", name, err)
		}
	}
	if out.Len() > 0 {
		t.Errorf("out %q", out.String())
	}
}
