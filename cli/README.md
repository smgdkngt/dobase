# dobase CLI

`dobase` works with your Dobase tools from the terminal: boards, todos, docs,
chat, notifications, mail, calendar and files. It talks to the
[Dobase API](../docs/api/README.md) with a personal access token. It suits
scripts and AI assistants just as well as people.

It is a single Ruby program with no gems to install. It needs Ruby 3.1 or newer.

## Install

Link the script onto your `PATH`:

```bash
ln -s "$PWD/cli/dobase" /usr/local/bin/dobase
```

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
Install it by linking the directory into your skills:

```bash
ln -s "$PWD/cli" ~/.claude/skills/dobase
```

Run `dobase login` yourself first. Claude never needs to see your token.
