package commands

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	neturl "net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/term"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
	"github.com/smgdkngt/dobase/cli/internal/config"
)

// RunApp opens the full-screen app. The cli package sets it, so this package
// doesn't depend on the app.
var RunApp func(ctx *Ctx) error

func account() []*Definition {
	return []*Definition{
		New("login", "Sign this machine in: confirm a code in any browser (or paste a token with --token)", []string{"[URL]"},
			[]Flag{Switch("token", "Paste a personal access token from Profile → API instead")}, login),
		New("logout", "Sign this machine out (a pasted token keeps working until you revoke it under Profile → API)", nil, nil, logout),
		New("whoami", "Show who the token belongs to and what it may do", nil, nil, whoami),
		New("ui", "Open the interactive app (what dobase does without arguments in a terminal)", nil, nil, ui),
	}
}

func login(ctx *Ctx, args *Args) error {
	url := args.Get(0)
	if url == "" {
		url = ctx.Config.URL()
	}
	if url == "" {
		answer, err := ask("Dobase URL: ", false)
		if err != nil {
			return err
		}
		url = answer
	}
	url = strings.TrimRight(strings.TrimSpace(url), "/")
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		url = "https://" + url
	}

	// A token on stdin (a script) or --token is pasted; someone at a terminal confirms a code
	if args.On("token") || !term.IsTerminal(int(os.Stdin.Fd())) {
		return loginWithToken(ctx, url)
	}
	return loginWithCode(ctx, url)
}

func loginWithToken(ctx *Ctx, url string) error {
	fmt.Fprintf(os.Stderr, "Create an access token under Profile → API: %s/profile/edit?tab=api\n", url)
	token, err := ask("Access token: ", true)
	if err != nil {
		return err
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return api.Usagef("No token given.")
	}

	server, err := api.NewMCP(url, api.Static(token), ctx.UserAgent)
	if err != nil {
		return err
	}
	ctx.SetAPI(server)
	profile, err := ctx.Call("whoami", nil)
	if err != nil {
		return err
	}
	if err := ctx.Config.Save(url, token); err != nil {
		return err
	}
	signedIn(ctx, url, profile)
	return nil
}

// loginWithCode is OAuth's device flow: the server gives a code, the person
// confirms it in a browser where they are signed in (any device), and the
// tokens arrive here. Nothing to copy, and no browser needed on this machine.
func loginWithCode(ctx *Ctx, url string) error {
	host, _ := os.Hostname()
	client, status, err := config.PostJSON(url+"/oauth/register", map[string]any{
		"client_name": strings.TrimSpace("dobase CLI " + host), "redirect_uris": []string{"http://127.0.0.1/"},
		"grant_types": []string{"urn:ietf:params:oauth:grant-type:device_code", "refresh_token"},
	})
	if err != nil {
		return err
	}
	if status != 201 {
		return api.Failf("%s has no OAuth login (HTTP %d). Use `dobase login --token`.", url, status)
	}
	clientID := client.Get("client_id").S()

	device, _, err := config.PostForm(url+"/oauth/device_authorization", neturl.Values{"client_id": {clientID}})
	if err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "Open %s and confirm the code %s\n", device.Get("verification_uri_complete").S(), device.Get("user_code").S())
	fmt.Fprintf(os.Stderr, "(or go to %s and type it). Waiting…\n", device.Get("verification_uri").S())

	interval := time.Duration(max(device.Get("interval").Int(), 1)) * time.Second
	deadline := time.Now().Add(time.Duration(device.Get("expires_in").Int()) * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(interval)
		tokens, _, err := config.PostForm(url+"/oauth/token", neturl.Values{
			"grant_type": {"urn:ietf:params:oauth:grant-type:device_code"}, "device_code": {device.Get("device_code").S()}, "client_id": {clientID},
		})
		if err != nil {
			return err
		}
		switch tokens.Get("error").S() {
		case "":
			if err := ctx.Config.SaveOAuth(url, clientID, tokens); err != nil {
				return err
			}
			ctx.SetAPI(nil)
			profile, err := ctx.Call("whoami", nil)
			if err != nil {
				return err
			}
			signedIn(ctx, url, profile)
			return nil
		case "authorization_pending":
		case "slow_down":
			interval += 5 * time.Second
		case "access_denied":
			return api.Failf("Not connected: it was denied in the browser.")
		default:
			return api.Failf("Not connected: %s. Run `dobase login` again.", tokens.Get("error").S())
		}
	}
	return api.Failf("The code ran out before it was confirmed. Run `dobase login` again.")
}

func signedIn(ctx *Ctx, url string, profile api.Value) {
	ctx.Sayf("Signed in to %s as %s.", url, Person(profile))
	permission := "only read"
	if profile.Get("access_token", "permission").S() == "write" {
		permission = "read and write"
	}
	ctx.Sayf("Token %s can %s%s.", Quoted(profile.Get("access_token", "name").S()), permission,
		If(profile.Get("access_token", "agent").Truthy(), ", and posts as itself for you"))
}

func logout(ctx *Ctx, _ *Args) error {
	// A login by code ends on the server too; a pasted token is the person's to revoke
	ended := ctx.Config.EndOAuth()
	if err := ctx.Config.Forget(); err != nil {
		return err
	}
	if ended {
		ctx.Say("Signed out.")
	} else {
		ctx.Say("Signed out. The token still works until you revoke it under Profile → API.")
	}
	return nil
}

func whoami(ctx *Ctx, _ *Args) error {
	profile, err := ctx.Me()
	if err != nil {
		return err
	}
	return ctx.Output(profile, func() error {
		ctx.Sayf("%s on %s", Person(profile), ctx.Config.URL())
		if token := profile.Get("access_token"); !token.IsNull() {
			permission := "read only"
			if token.Get("permission").S() == "write" {
				permission = "read and write"
			}
			ctx.Sayf("Token %s (%s%s)", Quoted(token.Get("name").S()), permission,
				If(token.Get("agent").Truthy(), ", posts as itself"))
		}
		return nil
	})
}

func ui(ctx *Ctx, _ *Args) error {
	if !term.IsTerminal(int(os.Stdin.Fd())) || !term.IsTerminal(int(os.Stdout.Fd())) {
		return api.Usagef("The app needs a terminal to draw in. Scripts can use the commands instead: dobase help")
	}
	return RunApp(ctx)
}

// ask prompts only when someone is typing; a piped token is read silently.
func ask(prompt string, secret bool) (string, error) {
	stdin := int(os.Stdin.Fd())
	if !term.IsTerminal(stdin) {
		return readLine()
	}
	fmt.Fprint(os.Stderr, prompt)
	if !secret {
		return readLine()
	}
	answer, err := term.ReadPassword(stdin)
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", api.Failf("Could not read the answer: %v", err)
	}
	return string(answer), nil
}

func readLine() (string, error) {
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" && !errors.Is(err, io.EOF) {
		return "", api.Failf("Could not read the answer: %v", err)
	}
	return line, nil
}
