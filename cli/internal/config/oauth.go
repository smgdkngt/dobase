package config

import (
	"bytes"
	"fmt"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/smgdkngt/dobase/cli/internal/api"
)

// Credentials are what the CLI signs in with: DOBASE_TOKEN, the login's
// OAuth tokens (`dobase login` by the device flow), or a personal token that
// was pasted in.
func (c *Config) Credentials() api.Credentials {
	if token := os.Getenv("DOBASE_TOKEN"); token != "" {
		return api.Static(token)
	}
	if !c.load().Get("oauth").IsNull() {
		return &oauth{config: c}
	}
	return api.Static(c.load().Get("token").S())
}

// SaveOAuth keeps a login's tokens, as the token endpoint gave them.
func (c *Config) SaveOAuth(url, clientID string, tokens api.Value) error {
	expires := time.Now().Add(time.Duration(tokens.Get("expires_in").Int()) * time.Second).UTC().Format(time.RFC3339)
	return c.write(api.Object("url", strings.TrimRight(url, "/"), "oauth", api.Object(
		"client_id", clientID,
		"access_token", tokens.Get("access_token"),
		"refresh_token", tokens.Get("refresh_token"),
		"expires_at", expires,
	)))
}

// oauth hands out the login's access token, and a new one once it has run
// out. Every `dobase` on the machine shares the saved tokens, and a refresh
// token that is used twice ends the login on the server: so a refresh happens
// with the config locked, after reading it again, and is skipped when another
// process got there first.
type oauth struct {
	config *Config
}

// Refreshed this long before it runs out, so a request never leaves with a token about to expire
const margin = time.Minute

func (o *oauth) Token() (string, error) {
	saved := o.config.load().Get("oauth")
	expires, err := time.Parse(time.RFC3339, saved.Get("expires_at").S())
	if err == nil && time.Until(expires) > margin {
		return saved.Get("access_token").S(), nil
	}
	return o.Refresh(saved.Get("access_token").S())
}

func (o *oauth) Refresh(refused string) (string, error) {
	path := Path() + ".lock"
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", api.PathError(path, err)
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return "", api.PathError(path, err)
	}
	defer file.Close()
	if err := lock(file); err != nil {
		return "", api.PathError(path, err)
	}
	defer unlock(file)

	o.config.loaded = false
	saved := o.config.load().Get("oauth")
	if saved.IsNull() {
		return "", &api.Error{Kind: api.Failed, Message: "Signed out. Run `dobase login URL` again.", Status: http.StatusUnauthorized}
	}
	expires, _ := time.Parse(time.RFC3339, saved.Get("expires_at").S())
	if current := saved.Get("access_token").S(); current != refused && time.Until(expires) > margin {
		return current, nil
	}

	form := url.Values{"grant_type": {"refresh_token"}, "refresh_token": {saved.Get("refresh_token").S()}, "client_id": {saved.Get("client_id").S()}}
	tokens, status, err := PostForm(o.config.URL()+"/oauth/token", form)
	if err != nil {
		return "", err
	}
	if status != http.StatusOK {
		return "", &api.Error{Kind: api.Failed, Status: http.StatusUnauthorized,
			Message: fmt.Sprintf("The login has ended (%s). Run `dobase login %s` again.", tokens.Get("error").Or("refused"), o.config.URL())}
	}
	if err := o.config.SaveOAuth(o.config.URL(), saved.Get("client_id").S(), tokens); err != nil {
		return "", err
	}
	return tokens.Get("access_token").S(), nil
}

// EndOAuth revokes a login's tokens on the server (RFC 7009), and says whether there was one.
func (c *Config) EndOAuth() bool {
	saved := c.load().Get("oauth")
	if saved.IsNull() {
		return false
	}
	PostForm(c.URL()+"/oauth/revoke", url.Values{"token": {saved.Get("refresh_token").S()}, "client_id": {saved.Get("client_id").S()}})
	return true
}

// PostJSON posts JSON (client registration) and returns the answer's JSON and status.
func PostJSON(target string, body any) (api.Value, int, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return api.Null, 0, api.Failf("Can't send %v: %v", body, err)
	}
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Post(target, "application/json", bytes.NewReader(data))
	return answer(target, response, err)
}

// PostForm posts a form to an OAuth endpoint and returns its JSON and status.
func PostForm(target string, form url.Values) (api.Value, int, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.PostForm(target, form)
	return answer(target, response, err)
}

func answer(target string, response *http.Response, err error) (api.Value, int, error) {
	if err != nil {
		return api.Null, 0, api.Failf("Could not reach %s: %v", target, err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return api.Null, response.StatusCode, api.Failf("Could not read what %s answered: %v", target, err)
	}
	value, err := api.Parse(body)
	if err != nil {
		return api.Null, response.StatusCode, api.Failf("%s answered something other than JSON (HTTP %d).", target, response.StatusCode)
	}
	return value, response.StatusCode, nil
}
