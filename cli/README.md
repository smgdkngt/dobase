# dobase CLI

`dobase` works with your Dobase tools from the terminal: boards, todos, docs,
chat, notifications, mail, calendar and files. It talks to the
[Dobase API](../docs/api/README.md) with a personal access token. It suits
scripts and AI assistants just as well as people.

It is a single program with nothing else to install, built for macOS, Linux
and Windows with every [release](https://github.com/smgdkngt/dobase/releases).

## Install

On macOS or Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/smgdkngt/dobase/main/cli/install.sh | sh
```

The script downloads the build for your machine from the latest release,
checks its checksum and puts `dobase` in `~/.local/bin`. Set
`DOBASE_INSTALL_DIR` to put it elsewhere, or `DOBASE_VERSION` (a release such as
`2026.09.24`) to match an older Dobase server.

On Windows, download `dobase-x86_64-pc-windows-msvc.zip` from the
[latest release](https://github.com/smgdkngt/dobase/releases/latest) and put
`dobase.exe` somewhere on your `PATH`.

`dobase --version` shows which release you have.

Then sign in. In the browser, create a token under **Profile → API**, then run:

```bash
dobase login https://dobase.example.com
```

`login` asks for the token and saves the URL and token to
`~/.config/dobase/config.json`, readable only by you. `DOBASE_URL` and
`DOBASE_TOKEN` override the saved values, which is handy for scripts or a
second instance:

```bash
DOBASE_URL=http://localhost:3000 DOBASE_TOKEN=dobase_... dobase tool list
```

Pick **Read only** if you only want to look things up. A read-only token
can't change anything.

## Look around

Run `dobase` without anything after it and it opens as a full-screen app:
your tools and what's new, boards with their columns side by side, todo lists,
chats that keep up by themselves, documents, your agenda, files and mail.

```
     _       _
  __| | ___ | |__   __ _ ___  ___
 / _` |/ _ \| '_ \ / _` / __|/ _ \
| (_| | (_) | |_) | (_| \__ \  __/
 \__,_|\___/|_.__/ \__,_|___/\___|
```

Arrow keys (or `h j k l`) move, `enter` opens, `esc` goes back and `?` shows
the keys of the screen you're on. On a board, `c` adds a card and `H`/`L` move
it to the previous or next column; in a todo list, `space` ticks a todo off;
`e` renames and `d` sets a due date (`fri`, `+3`, `tomorrow`). In a chat, `i`
starts a message and scrolling up past the top loads older ones. Made a
mistake? `u` undoes the last change. `/` searches everything, `n` shows your
notifications, `]` and `[` hop between tools, and `o` opens whatever you're
looking at in the browser. `q` quits.

`o` and `--open` (on mail drafts) use Dobase installed as an app when there is
one: Safari's web app at `~/Applications/Dobase.app` on a Mac, or a Chrome, Edge
or Vivaldi app, which opens `web+dobase://` links. Otherwise they use your
browser. Set `DOBASE_APP` to the app to use when yours has another name, e.g.
`DOBASE_APP="/Applications/Our Tools.app"`.

Boards, todos, chats and your notifications keep up by themselves while you
look at them.

`dobase ui` does the same. When the output goes to a script or a pipe, plain
`dobase` prints the help instead.

## Use

```bash
dobase tool list                              # your tools, with ids and types
dobase card list "Product Launch"             # a board's columns and cards
dobase card create "Product Launch" "Fix login" --column "To Do" --assignee me --due tomorrow
dobase card move 1/21 Done
dobase todo finish 3/55
dobase doc show 4/9
dobase chat post "Team Chat" "Deploy is done"
dobase chat post "Team Chat" "The mockups" --attach home.png --attach cart.png
dobase help                                   # everything; `dobase help card` for one noun
```

- **TOOL** is a tool id or a unique part of its name.
- Things inside a tool are **TOOL/ID**, such as `1/21`. List commands print them.
- A **TEXT** value of `-` is read from stdin.
- `--html` sends formatted text as HTML.
- `--json` prints the raw API response.

## Themes

```bash
dobase theme list                             # the built-in themes, * is yours
dobase theme set tokyo-night                  # `default` goes back to Dobase's own look
dobase theme font mono                        # everything in your monospace font; `default` undoes it
dobase theme sync                             # wear the theme your Omarchy desktop is on
dobase theme follow                           # ...and keep following it
```

On [Omarchy](https://omarchy.org), `dobase theme sync` reads the current theme's
`colors.toml` and sends its colours, so themes you installed or made yourself
come along too. `dobase theme follow` writes
`~/.config/omarchy/hooks/theme-set.d/dobase`, which Omarchy runs on every theme
switch; open Dobase pages change colour on the spot. `dobase theme follow --stop`
removes the hook. Anything else that has a `colors.toml` in that format works
with `dobase theme sync --file PATH --name NAME`.

The full-screen app wears your theme too: its accent, selection, card labels and
logo take the theme's colours, and it follows a switch within ten seconds.

## With Claude Code

This directory is also a Claude Code skill. `SKILL.md` tells Claude when and
how to use the CLI, including rules about sending mail, posting and deleting.
Install `dobase` as above, then copy the skill into your skills:

```bash
mkdir -p ~/.claude/skills/dobase
curl -fsSL https://raw.githubusercontent.com/smgdkngt/dobase/main/cli/SKILL.md -o ~/.claude/skills/dobase/SKILL.md
```

Run `dobase login` yourself first. Claude never needs to see your token.

## Development

The CLI is written in Go and lives in this directory, next to the app whose
API it uses. Build and test it with the Go tools:

```bash
go build .                   # ./dobase
go test ./...                # also checks that the commands in these docs exist
go vet ./...
gofmt -l .
```

Try it against `bin/dev` with `DOBASE_URL=http://localhost:3010` and a token
from Profile → API in `DOBASE_TOKEN` (`go run . tool list`).

The full-screen app lives in `internal/tui/`, drawn with
[tcell](https://github.com/gdamore/tcell). Its tests drive it with key presses
against a fake server on a simulated screen.

Commands are declared per noun in `internal/commands/*.go` with
`New("noun verb", summary, []string{ARGS}, []Flag{flags}, function)`; `dobase help`
is generated from those. Publishing a GitHub release builds the binaries and
attaches them to it (`.github/workflows/cli-release.yml`).
