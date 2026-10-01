package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Method is an HTTP method.
type Method string

const (
	Get    Method = http.MethodGet
	Post   Method = http.MethodPost
	Patch  Method = http.MethodPatch
	Delete Method = http.MethodDelete
)

// Param is a query parameter.
type Param struct{ Name, Value string }

// FilePart pairs a form field with a local path, for uploads.
type FilePart struct{ Field, Path string }

// API is what commands need from the server. Tests swap in a fake.
type API interface {
	// Request sends body (nil for none) as JSON. Null means the server sent no content.
	Request(method Method, path string, params []Param, body any) (Value, error)
	// Upload is a multipart POST of files and text fields.
	Upload(path string, files []FilePart, fields []Param) (Value, error)
	// Download streams path to destination, following redirects, and returns
	// the filename the server suggested, if any.
	Download(path, destination string) (string, error)
}

// Client talks JSON over HTTP to a Dobase server.
type Client struct {
	base      *url.URL
	token     string
	userAgent string
	http      *http.Client
}

// NewClient needs a URL and a token.
func NewClient(serverURL, token, userAgent string) (*Client, error) {
	if serverURL == "" || token == "" {
		return nil, Failf("Not signed in. Run `dobase login URL` first, or set DOBASE_URL and DOBASE_TOKEN.")
	}
	base, err := url.Parse(strings.TrimRight(serverURL, "/") + "/")
	if err != nil || base.Scheme == "" || base.Host == "" {
		return nil, Failf("%s is not a URL.", serverURL)
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.DialContext = (&net.Dialer{Timeout: 10 * time.Second}).DialContext
	transport.ResponseHeaderTimeout = 60 * time.Second
	client := &http.Client{
		Transport: transport,
		// Redirects are answered by hand, so the token never follows one elsewhere.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	return &Client{base: base, token: token, userAgent: userAgent, http: client}, nil
}

func (c *Client) urlFor(path string) (*url.URL, error) {
	var target *url.URL
	var err error
	if strings.HasPrefix(path, "http://") || strings.HasPrefix(path, "https://") {
		target, err = url.Parse(path)
	} else {
		var relative *url.URL
		relative, err = url.Parse(strings.TrimLeft(path, "/"))
		if err == nil {
			target = c.base.ResolveReference(relative)
		}
	}
	if err != nil {
		return nil, Failf("Can't make a URL of %s", path)
	}
	return target, nil
}

// The token only goes to the configured server, never to a redirect target elsewhere.
func (c *Client) newRequest(method Method, target *url.URL, body io.Reader) (*http.Request, error) {
	request, err := http.NewRequest(string(method), target.String(), body)
	if err != nil {
		return nil, Failf("Can't make a request to %s: %v", target, err)
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", c.userAgent)
	if target.Hostname() == c.base.Hostname() && port(target) == port(c.base) {
		request.Header.Set("Authorization", "Bearer "+c.token)
	}
	return request, nil
}

func port(u *url.URL) string {
	if p := u.Port(); p != "" {
		return p
	}
	if u.Scheme == "http" {
		return "80"
	}
	return "443"
}

func (c *Client) do(request *http.Request) (*http.Response, error) {
	response, err := c.http.Do(request)
	if err != nil {
		var reason error = err
		if urlErr, ok := err.(*url.Error); ok {
			reason = urlErr.Err
		}
		return nil, Failf("Could not reach %s: %v", strings.TrimRight(c.base.String(), "/"), reason)
	}
	return response, nil
}

func (c *Client) json(response *http.Response) (Value, error) {
	defer response.Body.Close()
	status := response.StatusCode
	if status == http.StatusNoContent {
		return Null, nil
	}
	if status >= 300 && status < 400 {
		return Null, Failf("The server redirected to %s instead of answering. This action may not be available through the API.", response.Header.Get("Location"))
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return Null, Failf("Could not read the response: %v", err)
	}
	if status < 200 || status >= 300 {
		return Null, apiError(status, body)
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return Null, nil
	}
	value, err := Parse(body)
	if err != nil {
		return Null, Failf("The server sent something other than JSON (HTTP %d).", status)
	}
	return value, nil
}

func (c *Client) Request(method Method, path string, params []Param, body any) (Value, error) {
	target, err := c.urlFor(path)
	if err != nil {
		return Null, err
	}
	if len(params) > 0 {
		query := make([]string, 0, len(params))
		for _, param := range params {
			query = append(query, url.QueryEscape(param.Name)+"="+url.QueryEscape(param.Value))
		}
		if target.RawQuery != "" {
			target.RawQuery += "&"
		}
		target.RawQuery += strings.Join(query, "&")
	}

	var reader io.Reader
	if !emptyBody(body) {
		data, err := json.Marshal(body)
		if err != nil {
			return Null, Failf("Can't send %v: %v", body, err)
		}
		reader = bytes.NewReader(data)
	}
	request, err := c.newRequest(method, target, reader)
	if err != nil {
		return Null, err
	}
	if reader != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := c.do(request)
	if err != nil {
		return Null, err
	}
	return c.json(response)
}

func emptyBody(body any) bool {
	switch body := body.(type) {
	case nil:
		return true
	case Value:
		return body.IsNull() || (body.IsObject() && len(body.Keys()) == 0)
	case map[string]any:
		return len(body) == 0
	}
	return false
}

func (c *Client) Upload(path string, files []FilePart, fields []Param) (Value, error) {
	target, err := c.urlFor(path)
	if err != nil {
		return Null, err
	}

	// The form is streamed: text parts in memory, files read from disk as they're sent.
	boundary := fmt.Sprintf("dobase-%x%x", os.Getpid(), time.Now().UnixNano())
	var parts []io.Reader
	var length int64

	text := func(part string) {
		length += int64(len(part))
		parts = append(parts, strings.NewReader(part))
	}
	for _, field := range fields {
		text(fmt.Sprintf("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n", boundary, escapeQuotes(field.Name), field.Value))
	}
	for _, file := range files {
		opened, err := os.Open(file.Path)
		if err != nil {
			return Null, PathError(file.Path, err)
		}
		defer opened.Close()
		info, err := opened.Stat()
		if err != nil {
			return Null, PathError(file.Path, err)
		}
		text(fmt.Sprintf("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n",
			boundary, escapeQuotes(file.Field), escapeQuotes(filepath.Base(file.Path)), contentTypeFor(file.Path)))
		length += info.Size()
		parts = append(parts, opened)
		text("\r\n")
	}
	text("--" + boundary + "--\r\n")

	request, err := c.newRequest(Post, target, io.MultiReader(parts...))
	if err != nil {
		return Null, err
	}
	request.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)
	request.ContentLength = length
	response, err := c.do(request)
	if err != nil {
		return Null, err
	}
	return c.json(response)
}

func (c *Client) Download(path, destination string) (string, error) {
	target, err := c.urlFor(path)
	if err != nil {
		return "", err
	}

	for range 6 {
		request, err := c.newRequest(Get, target, nil)
		if err != nil {
			return "", err
		}
		response, err := c.do(request)
		if err != nil {
			return "", err
		}
		status := response.StatusCode

		if status >= 300 && status < 400 {
			location := response.Header.Get("Location")
			response.Body.Close()
			next, err := target.Parse(location)
			if err != nil {
				return "", Failf("The server redirected to %s, which isn't a URL.", location)
			}
			target = next
			continue
		}
		if status < 200 || status >= 300 {
			body, _ := io.ReadAll(response.Body)
			response.Body.Close()
			return "", apiError(status, body)
		}

		filename := ""
		if _, rest, ok := strings.Cut(response.Header.Get("Content-Disposition"), "filename=\""); ok {
			filename, _, _ = strings.Cut(rest, "\"")
		}
		file, err := os.Create(destination)
		if err != nil {
			response.Body.Close()
			return "", PathError(destination, err)
		}
		_, err = io.Copy(file, response.Body)
		response.Body.Close()
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			// Part of a file passes for the file: better none.
			os.Remove(destination)
			return "", Failf("Download failed: %v", err)
		}
		return filename, nil
	}
	return "", Failf("Too many redirects")
}

// DownloadWhole downloads like server.Download and then checks that the file
// is size bytes long: its size as the API gave it, or null when there's none
// to check. A server that fails halfway can end a download as if it were
// done; a file that came up short is removed.
func DownloadWhole(server API, path, destination string, size Value) (string, error) {
	filename, err := server.Download(path, destination)
	if err != nil || size.IsNull() {
		return filename, err
	}
	info, err := os.Stat(destination)
	if err != nil {
		return "", PathError(destination, err)
	}
	if info.Size() != size.Int() {
		os.Remove(destination)
		return "", Failf("Download failed: %s came in at %d of %d bytes. Try again.", filepath.Base(destination), info.Size(), size.Int())
	}
	return filename, nil
}

// PathError is a failed file operation, worded like "PATH: reason".
func PathError(path string, err error) error {
	if pathErr, ok := err.(*os.PathError); ok {
		err = pathErr.Err
	}
	return Failf("%s: %v", path, err)
}

func apiError(status int, body []byte) error {
	var message string
	if data, err := Parse(body); err == nil {
		errs := data.Get("errors")
		if errs.IsNull() {
			errs = data.Get("error")
		}
		if errs.IsArray() {
			texts := make([]string, 0, len(errs.Items()))
			for _, item := range errs.Items() {
				texts = append(texts, item.S())
			}
			message = strings.Join(texts, ", ")
		} else {
			message = errs.S()
		}
	} else {
		line, _, _ := strings.Cut(strings.TrimSpace(string(body)), "\n")
		line = strings.TrimSpace(line)
		if line == "" {
			message = "Request failed"
		} else {
			runes := []rune(line)
			if len(runes) > 200 {
				runes = runes[:200]
			}
			message = string(runes)
		}
	}
	return Failf("%s (HTTP %s)", message, strconv.Itoa(status))
}

func escapeQuotes(text string) string {
	return strings.NewReplacer("\"", "%22", "\r", " ", "\n", " ").Replace(text)
}

func contentTypeFor(path string) string {
	switch strings.ToLower(strings.TrimPrefix(filepath.Ext(path), ".")) {
	case "csv":
		return "text/csv"
	case "doc":
		return "application/msword"
	case "docx":
		return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
	case "gif":
		return "image/gif"
	case "htm", "html":
		return "text/html"
	case "ics":
		return "text/calendar"
	case "jpeg", "jpg":
		return "image/jpeg"
	case "json":
		return "application/json"
	case "md":
		return "text/markdown"
	case "mov":
		return "video/quicktime"
	case "mp3":
		return "audio/mpeg"
	case "mp4":
		return "video/mp4"
	case "ogg":
		return "audio/ogg"
	case "pdf":
		return "application/pdf"
	case "png":
		return "image/png"
	case "ppt":
		return "application/vnd.ms-powerpoint"
	case "pptx":
		return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
	case "svg":
		return "image/svg+xml"
	case "txt":
		return "text/plain"
	case "wav":
		return "audio/wav"
	case "webm":
		return "video/webm"
	case "webp":
		return "image/webp"
	case "xls":
		return "application/vnd.ms-excel"
	case "xlsx":
		return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	case "zip":
		return "application/zip"
	}
	return "application/octet-stream"
}
