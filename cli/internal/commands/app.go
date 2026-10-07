package commands

import (
	"github.com/smgdkngt/dobase/cli/internal/api"
	. "github.com/smgdkngt/dobase/cli/internal/command"
)

func app() []*Definition {
	return []*Definition{
		New("app install", "Make Dobase an app of its own here, or bring that app up to date", nil,
			[]Flag{F("electron", "PATH", "An Electron of your own to run it in: its zip, or on Linux its program (default: the system's, else the newest release)")}, installApp),
		New("app open", "Open the app `dobase app install` made", nil, nil, openApp),
		New("app remove", "Take that app away again, and the sign-in it kept", nil, nil, removeApp),
	}
}

func installApp(ctx *Ctx, args *Args) error {
	server, err := appServer(ctx)
	if err != nil {
		return err
	}
	tell := ctx.Say
	if ctx.JSON {
		tell = func(string) {}
	}
	_, had := InstalledApp(server)
	app, err := InstallApp(server, args.Value("electron"), tell)
	if err != nil {
		return err
	}
	if err := app.Show(""); err != nil {
		return api.Failf("%s is installed, but it didn't open: %v", app.Name, err)
	}
	return ctx.Output(api.Object("name", app.Name, "url", app.Server, "path", app.Path, "data", app.Data, "electron", app.Electron), func() error {
		if had {
			ctx.Sayf("%s is up to date, and still signed in.", app.Name)
		} else {
			ctx.Sayf("%s is an app of its own now, apart from your browser.", app.Name)
			ctx.Say("Sign in once in the window that opens. `--open` and `o` use this app from now on.")
		}
		ctx.Field("App", app.Path)
		ctx.Field("Electron", app.Electron+If(app.Electron == "", "the system's"))
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
	ctx.Sayf("The %s app is gone, with the sign-in it kept.", app.Name)
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
