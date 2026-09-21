# Dobase

An open-source, self-hosted workspace with installable tools. Add a mail client, kanban boards, documents, chat, file storage, calendars, to-do lists, or video rooms — each shared with collaborators you choose.

Built with Ruby on Rails 8.1, Hotwire, and Tailwind CSS.

![Dobase](site/demo.gif)

## Tools

| Tool | Description |
|------|-------------|
| **Mail** | IMAP/SMTP email with threaded conversations, search, drafts that sync, and calendar invites you accept from the message |
| **Board** | Kanban boards with labels, due dates, assignees, comments with @mentions, attachments, and an archive |
| **Docs** | Rich text documents several people write in at once, with each other's cursors shown live |
| **Chat** | Real-time messaging with replies, @mentions, edits, file sharing, and who's online and typing |
| **Todos** | Task lists with due dates, assignees, repeating tasks, comments, and attachments |
| **Files** | Folders, a picture gallery with slideshow, readable text, markdown and code, and public links with a password and expiry |
| **Calendar** | Syncs with any CalDAV server (iCloud, Fastmail, Nextcloud) or runs on its own; recurring events and invites |
| **Room** | Video calls powered by LiveKit, with screen sharing |

## Working together

- **Write in the same document.** Everyone types at once and the text merges as you go (Yjs, carried over Action Cable — no extra service). Each person's cursor shows in their own colour, with their name.
- **See who's where.** Faces in the sidebar and topbar show who's in each tool; the card, todo or file someone has open is ringed, and inside it you see them writing a comment.
- **Search everything.** <kbd>Cmd</kbd>+<kbd>K</kbd> jumps to any tool or action and searches cards, todos, documents, files, chat, events and mail at once.
- **Notifications and @mentions**, live in the app and as an email digest when you're away.

## API and command line

Everything in your tools is also reachable through a JSON API. Create a
personal access token under **Profile → API**; tokens are read-only or
read-and-write and can't touch account settings. See [docs/api](docs/api/README.md).

The [`dobase` CLI](cli/README.md) is built on that API and doubles as a Claude
Code skill, so an AI assistant can read your board, add todos or draft a reply
for you:

```bash
dobase login https://dobase.example.com
dobase card list "Product Launch"
dobase todo create "Launch Tasks" "Book the venue" --due tomorrow --assignee me
dobase search packaging
```

## Self-hosting

Dobase runs as a single Docker container. Everything — web server, background jobs, database — is included.

### Install with ONCE

The easiest way to self-host Dobase is with [ONCE](https://once.com) by 37signals. ONCE handles installation, updates, backups, and SSL — all from a simple terminal dashboard.

Point ONCE at:

```
ghcr.io/smgdkngt/dobase:latest
```

That's it. ONCE takes care of the rest — including SSL, persistent storage, and automatic backups. Works on any Linux server, cloud VPS, or even a Raspberry Pi.

All tools work out of the box except the Room (video) tool, which requires an external [LiveKit](https://livekit.io) server. ONCE runs a single container per app, so LiveKit needs to run separately — either via [LiveKit Cloud](https://livekit.io/cloud) or as a standalone Docker container. See [Video conferencing](#video-conferencing-livekit) for setup.

### Deploy with Kamal

For the complete experience — SSL, zero-downtime deploys, LiveKit as an accessory — use [Kamal](https://kamal-deploy.org). All you need is a VPS with Ubuntu.

```bash
git clone https://github.com/smgdkngt/dobase.git
cd dobase
```

Edit `config/deploy.yml` with your server IP and domain, then add secrets to `.kamal/secrets`:

```bash
# .kamal/secrets
SECRET_KEY_BASE=<generate with: bin/rails secret>
SMTP_USERNAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password
```

```bash
kamal setup    # First deploy — provisions server, builds image, starts app
kamal deploy   # Subsequent deploys
```

Kamal handles SSL certificates (Let's Encrypt), asset bridging, and rolling restarts automatically. LiveKit can run as a Kamal accessory — uncomment the `livekit` section in `config/deploy.yml`.

### Docker

```bash
docker run -d \
  -p 80:80 \
  -v dobase_storage:/rails/storage \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e DISABLE_SSL=true \
  ghcr.io/smgdkngt/dobase:latest
```

Visit `http://localhost` and sign up. Remove `DISABLE_SSL=true` when running behind a TLS proxy or with a domain.

### Docker Compose

For a persistent setup with all options, clone the repo and use the included `docker-compose.yml`:

```bash
git clone https://github.com/smgdkngt/dobase.git
cd dobase
SECRET_KEY_BASE=$(openssl rand -hex 64) docker compose up -d
```

Or create your own `docker-compose.yml`:

```yaml
services:
  web:
    image: ghcr.io/smgdkngt/dobase:latest
    ports:
      - "80:80"
    environment:
      - SECRET_KEY_BASE=<your-secret>
      - APP_HOST=your-domain.com
    volumes:
      - storage:/rails/storage
    restart: unless-stopped

volumes:
  storage:
```

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `SECRET_KEY_BASE` | — | **Required.** Generate with `openssl rand -hex 64` |
| `APP_NAME` | `Dobase` | App name in UI, emails, page titles |
| `APP_HOST` | `localhost:3000` | Host for mailer URLs |
| `APP_LOGO_PATH` | `/icon.svg` | Logo path (sidebar, auth pages) |
| `APP_FROM_EMAIL` | `notifications@dobase.co` | Sender address for emails |
| `DISABLE_SSL` | — | Set to `true` for non-TLS deployments (ONCE sets this automatically on localhost) |
| `OPEN_REGISTRATION` | — | Set to `true` to allow public signup (default: invite-only) |
| `SENTRY_DSN` | — | Report errors to a Sentry-compatible collector — self-hosted [Bugsink](https://www.bugsink.com) or GlitchTip work. Off when unset; nothing leaves the server |
| `SENTRY_ENV` | Rails environment | Name this installation in those reports |
| `ALLOW_PRIVATE_NETWORK_HOSTS` | — | Set to `true` to let mail and calendar accounts use servers on a private network (10.x, 172.16–31.x, 192.168.x). Local addresses are always refused |

#### Email (SMTP)

Email sending requires SMTP configuration. Without it, all other features work fine — invitation and notification emails just won't be sent.

| Variable | Default | Purpose |
|----------|---------|---------|
| `SMTP_ADDRESS` | — | SMTP server hostname |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USERNAME` | — | SMTP username |
| `SMTP_PASSWORD` | — | SMTP password |

#### Video conferencing (LiveKit)

The Room tool requires a [LiveKit](https://livekit.io) server. All other tools work without it.

LiveKit runs as a separate container — browsers connect to it directly via WebSocket, so it needs its own public URL.

| Method | How to run LiveKit |
|--------|--------------------|
| **Docker Compose** | Uncomment the `livekit` service in `docker-compose.yml` |
| **Docker** | Run `docker run -d -p 7880:7880 -p 7881:7881 -e LIVEKIT_KEYS=key:secret livekit/livekit-server` |
| **Kamal** | Uncomment the `livekit` accessory in `config/deploy.yml` |
| **ONCE** | Run LiveKit separately, or use [LiveKit Cloud](https://livekit.io/cloud) |

| Variable | Default | Purpose |
|----------|---------|---------|
| `LIVEKIT_URL` | — | **Public** WebSocket URL browsers connect to (e.g. `wss://room.your-domain.com`) |
| `LIVEKIT_API_KEY` | — | LiveKit API key |
| `LIVEKIT_API_SECRET` | — | LiveKit API secret |

Example with Docker Compose (uncomment in `docker-compose.yml`):

```yaml
livekit:
  image: livekit/livekit-server:latest
  ports:
    - "7880:7880"
    - "7881:7881"
  environment:
    - LIVEKIT_KEYS=your-api-key:your-api-secret
  restart: unless-stopped
```

Then add to the web service environment:

```yaml
- LIVEKIT_URL=wss://room.your-domain.com
- LIVEKIT_API_KEY=your-api-key
- LIVEKIT_API_SECRET=your-api-secret
```

### Storage & backups

All data lives in `/rails/storage` (SQLite database + uploaded files). Back up this volume regularly.

## Development

### Requirements

- Ruby 3.4+
- SQLite 3
- libvips (for image processing)

### Setup

```bash
git clone https://github.com/smgdkngt/dobase.git
cd dobase
bin/setup
```

Or manually:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

The app runs at `http://localhost:3000`.

### Demo data

Seed the database with a fictional company ("Moonshot Snacks") to explore all tools:

```bash
SEED_DEMO=1 bin/rails db:seed
```

Log in as `sophie@moonshot-snacks.com` / `password123`.

### Commands

```bash
bin/dev                    # Start dev server (Rails + Tailwind watcher)
bin/rails test             # Run tests
bin/rails test:system      # Run system tests
bin/rubocop                # Lint Ruby
bin/brakeman --quiet       # Security analysis
```

## License

[MIT License](LICENSE.md)
