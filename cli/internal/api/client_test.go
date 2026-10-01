package api

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestADownloadThatBreaksOffFailsAndLeavesNoFile(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/whole" {
			w.Header().Set("Content-Disposition", `attachment; filename="plan.pdf"`)
			w.Write([]byte("all of it"))
			return
		}
		// A hundred bytes are promised; the connection drops after ten.
		w.Header().Set("Content-Length", "100")
		w.Write([]byte("0123456789"))
		w.(http.Flusher).Flush()
		connection, _, err := w.(http.Hijacker).Hijack()
		if err == nil {
			connection.Close()
		}
	}))
	defer server.Close()
	client, err := NewClient(server.URL, "token", "test")
	if err != nil {
		t.Fatal(err)
	}

	destination := filepath.Join(t.TempDir(), "plan.pdf")
	if _, err := client.Download("/broken", destination); err == nil || !strings.HasPrefix(err.Error(), "Download failed: ") {
		t.Errorf("got %v", err)
	}
	if _, err := os.Stat(destination); !os.IsNotExist(err) {
		t.Errorf("the partial file is still there: %v", err)
	}

	filename, err := client.Download("/whole", destination)
	if data, _ := os.ReadFile(destination); err != nil || filename != "plan.pdf" || string(data) != "all of it" {
		t.Errorf("got %q in %q, %v", data, filename, err)
	}
}
