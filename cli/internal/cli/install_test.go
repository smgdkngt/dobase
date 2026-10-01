package cli

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestTheInstallerSaysSoWhenNothingCanCheckTheDownload(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("install.sh is for macOS and Linux")
	}
	// A PATH with what the script needs, a curl that downloads nothing real, and no sha256sum or shasum
	bin := t.TempDir()
	for _, tool := range []string{"uname", "mktemp", "cut", "rm"} {
		path, err := exec.LookPath(tool)
		if err != nil {
			t.Skipf("no %s here", tool)
		}
		if err := os.Symlink(path, filepath.Join(bin, tool)); err != nil {
			t.Fatal(err)
		}
	}
	downloads := filepath.Join(bin, "downloads")
	curl := "#!/bin/sh\necho \"$2\" >> " + downloads + "\necho 'abc123  dobase.tar.gz' > \"$4\"\n"
	if err := os.WriteFile(filepath.Join(bin, "curl"), []byte(curl), 0o755); err != nil {
		t.Fatal(err)
	}

	installer := exec.Command("/bin/sh", "../../install.sh")
	installer.Env = []string{"PATH=" + bin, "HOME=" + t.TempDir()}
	output, err := installer.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "needs sha256sum or shasum") || strings.Contains(string(output), "doesn't match") {
		t.Errorf("%v: %s", err, output)
	}
	if _, err := os.Stat(downloads); !os.IsNotExist(err) {
		t.Errorf("it downloaded before finding out: %s", output)
	}
}

func TestTheInstallerInstallsOnlyADownloadThatMatchesItsChecksum(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("install.sh is for macOS and Linux")
	}
	// A release of one program that says its version, served by a curl that copies files
	release := t.TempDir()
	var archive bytes.Buffer
	zipped := gzip.NewWriter(&archive)
	packed := tar.NewWriter(zipped)
	program := "#!/bin/sh\necho 'dobase 2026.10.01'\n"
	if err := packed.WriteHeader(&tar.Header{Name: "dobase", Mode: 0o755, Size: int64(len(program))}); err != nil {
		t.Fatal(err)
	}
	packed.Write([]byte(program))
	packed.Close()
	zipped.Close()
	os.WriteFile(filepath.Join(release, "archive"), archive.Bytes(), 0o644)
	curl := "#!/bin/sh\ncase \"$2\" in\n*.sha256) cp " + release + "/sha256 \"$4\" ;;\n*) cp " + release + "/archive \"$4\" ;;\nesac\n"
	if err := os.WriteFile(filepath.Join(release, "curl"), []byte(curl), 0o755); err != nil {
		t.Fatal(err)
	}

	install := func(checksum string) (string, string, error) {
		os.WriteFile(filepath.Join(release, "sha256"), []byte(checksum+"  dobase.tar.gz\n"), 0o644)
		directory := t.TempDir()
		installer := exec.Command("/bin/sh", "../../install.sh")
		installer.Env = []string{"PATH=" + release + ":" + os.Getenv("PATH"), "HOME=" + t.TempDir(), "DOBASE_INSTALL_DIR=" + directory}
		output, err := installer.CombinedOutput()
		return string(output), filepath.Join(directory, "dobase"), err
	}

	output, installed, err := install(fmt.Sprintf("%x", sha256.Sum256(archive.Bytes())))
	if err != nil || !strings.Contains(output, "Installed dobase 2026.10.01 to "+installed) {
		t.Errorf("%v: %s", err, output)
	}
	output, installed, err = install(strings.Repeat("0", 64))
	if err == nil || !strings.Contains(output, "doesn't match its checksum") {
		t.Errorf("%v: %s", err, output)
	}
	if _, err := os.Stat(installed); !os.IsNotExist(err) {
		t.Errorf("a download with the wrong checksum was installed: %v", err)
	}
}
