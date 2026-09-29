package commands

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"

	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

// RunApp opens the full-screen app. The cli package sets it, so this package
// doesn't depend on the app.
var RunApp func(ctx *Ctx) error

func account() []*Definition {
	return []*Definition{
		New("login", "Save the server URL and an access token for this machine", []string{"[URL]"}, nil, login),
		New("logout", "Forget the saved URL and token (revoke the token under Profile → API)", nil, nil, logout),
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

	fmt.Fprintf(os.Stderr, "Create an access token under Profile → API: %s/profile/edit?tab=api\n", url)
	token, err := ask("Access token: ", true)
	if err != nil {
		return err
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return api.Usagef("No token given.")
	}

	client, err := api.NewClient(url, token, ctx.UserAgent)
	if err != nil {
		return err
	}
	ctx.SetAPI(client)
	profile, err := ctx.Get("/profile")
	if err != nil {
		return err
	}
	if err := ctx.Config.Save(url, token); err != nil {
		return err
	}

	ctx.Sayf("Signed in to %s as %s.", url, Person(profile))
	permission := "only read"
	if profile.Get("access_token", "permission").S() == "write" {
		permission = "read and write"
	}
	ctx.Sayf("Token %s can %s.", Quoted(profile.Get("access_token", "name").S()), permission)
	return nil
}

func logout(ctx *Ctx, _ *Args) error {
	if err := ctx.Config.Forget(); err != nil {
		return err
	}
	ctx.Say("Signed out. The token still works until you revoke it under Profile → API.")
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
			ctx.Sayf("Token %s (%s)", Quoted(token.Get("name").S()), permission)
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
