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

func TestAnErrorFromTheServerKeepsItsStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error": "This folder has no share link"}`))
	}))
	defer server.Close()
	client, err := NewClient(server.URL, "token", "test")
	if err != nil {
		t.Fatal(err)
	}

	_, err = client.Request(Get, "/tools/5/files/folders/7/share", nil, nil)
	if err == nil || err.Error() != "This folder has no share link (HTTP 404)" || StatusOf(err) != http.StatusNotFound {
		t.Errorf("got %v, status %d", err, StatusOf(err))
	}
	if status := StatusOf(Failf("Could not reach the server")); status != 0 {
		t.Errorf("an error that isn't the server's has status %d", status)
	}
}
