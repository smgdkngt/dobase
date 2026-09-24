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
in a chat, `i` starts a message. `/` searches everything, `n` shows your
notifications, `]` and `[` hop between tools, and `o` opens whatever you're
looking at in the browser. `q` quits.

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
dobase help                                   # everything; `dobase help card` for one noun
```

- **TOOL** is a tool id or a unique part of its name.
- Things inside a tool are **TOOL/ID**, such as `1/21`. List commands print them.
- A **TEXT** value of `-` is read from stdin.
- `--html` sends formatted text as HTML.
- `--json` prints the raw API response.

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

The CLI is written in Rust and lives in this directory, next to the app whose
API it uses. Build and test it with Cargo:

```bash
cargo build                  # target/debug/dobase
cargo test                   # also checks that the commands in these docs exist
cargo clippy --all-targets
cargo fmt
```

Try it against `bin/dev` with `DOBASE_URL=http://localhost:3010` and a token
from Profile → API in `DOBASE_TOKEN`.

The full-screen app lives in `src/tui/`: one file per kind of tool in
`src/tui/screens/`, drawn with [ratatui](https://ratatui.rs). Its tests drive
it with key presses against a fake server on a virtual terminal.

Commands are declared per noun in `src/commands/*.rs` with
`command("noun verb", summary, &[ARGS], vec![flags], function)`; `dobase help`
is generated from those. Publishing a GitHub release builds the binaries and
attaches them to it (`.github/workflows/cli-release.yml`).
