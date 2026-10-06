package commands

import (
	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func app() []*Definition {
	return []*Definition{
		New("app install", "Make Dobase an app of its own here, kept apart from the browser you browse with", nil,
			[]Flag{F("browser", "PATH", "The browser that keeps it (default: Chromium, Chrome, Brave, Edge or Vivaldi, the first one here)")}, installApp),
		New("app open", "Open the app `dobase app install` made", nil, nil, openApp),
		New("app remove", "Take that app away again, and the sign-in it kept", nil, nil, removeApp),
	}
}

func installApp(ctx *Ctx, args *Args) error {
	server, err := appServer(ctx)
	if err != nil {
		return err
	}
	app, err := InstallApp(server, args.Value("browser"))
	if err != nil {
		return err
	}
	shortcut := app.Shortcut()
	if err := app.Show(""); err != nil {
		return api.Failf("%s is installed, but it didn't open: %v", app.Name, err)
	}
	return ctx.Output(api.Object("name", app.Name, "url", app.Server, "browser", app.Browser, "profile", app.Profile, "path", shortcut), func() error {
		ctx.Sayf("%s is an app of its own now, kept by %s in a profile nothing else uses.", app.Name, app.BrowserName())
		ctx.Say("Sign in once in the window that opens. `--open` and `o` use this app from now on.")
		ctx.Field("App", shortcut)
		ctx.Field("Profile", app.Profile)
		return nil
	})
}

func openApp(ctx *Ctx, _ *Args) error {
	app, err := installedApp(ctx)
	if err != nil {
		return err
	}
	if err := app.Show(""); err != nil {
		return api.Failf("%s didn't open: %v", app.Name, err)
	}
	return nil
}

func removeApp(ctx *Ctx, _ *Args) error {
	app, err := installedApp(ctx)
	if err != nil {
		return err
	}
	if err := app.Remove(); err != nil {
		return err
	}
	ctx.Sayf("The %s app is gone, with the sign-in it kept. %s itself is as it was.", app.Name, app.BrowserName())
	return nil
}

// appServer is the server an app is for; no token is needed to make one.
func appServer(ctx *Ctx) (string, error) {
	if server := ctx.Config.URL(); server != "" {
		return server, nil
	}
	return "", api.Failf("No server yet. Run `dobase login URL` first, or set DOBASE_URL.")
}

func installedApp(ctx *Ctx) (App, error) {
	server, err := appServer(ctx)
	if err != nil {
		return App{}, err
	}
	app, found := InstalledApp(server)
	if !found {
		return App{}, api.Failf("No app for %s here. `dobase app install` makes one.", server)
	}
	return app, nil
}
