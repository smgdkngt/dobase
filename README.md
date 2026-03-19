# Dobase

An open-source, self-hosted workspace with installable tools. Add a mail client, kanban boards, documents, chat, file storage, calendars, to-do lists, or video rooms — each shared with collaborators you choose.

Built with Ruby on Rails 8.1, Hotwire, and Tailwind CSS.

## Tools

| Tool | Description |
|------|-------------|
| **Mail** | IMAP/SMTP email client with rich text compose, contacts, and conversations |
| **Board** | Kanban boards with columns, cards, comments, and attachments |
| **Docs** | Rich text documents with real-time collaborative editing |
| **Chat** | Real-time messaging with typing indicators, replies, and file sharing |
| **Todos** | Task lists with due dates, assignments, comments, and attachments |
| **Files** | File storage with folders, sharing via public links, and previews |
| **Calendar** | CalDAV-compatible calendar with recurring events and local mode |
| **Room** | Video conferencing powered by LiveKit |

## Self-hosting

Dobase runs as a single Docker container. Everything — web server, background jobs, database — is included.

### Quick start

```bash
docker run -d \
  -p 80:80 \
  -v dobase_storage:/rails/storage \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  ghcr.io/smgdkngt/dobase:latest
```

Visit `http://localhost` and sign up.

### Docker Compose

For a persistent setup, create a `docker-compose.yml`:

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

```bash
docker compose up -d
```

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `SECRET_KEY_BASE` | — | **Required.** Generate with `openssl rand -hex 64` |
| `APP_NAME` | `Dobase` | App name in UI, emails, page titles |
| `APP_HOST` | `localhost:3000` | Host for mailer URLs |
| `APP_LOGO_PATH` | `/icon.svg` | Logo path (sidebar, auth pages) |
| `APP_FROM_EMAIL` | `notifications@dobase.co` | Sender address for emails |
| `SMTP_ADDRESS` | — | SMTP server for sending emails |
| `SMTP_PORT` | `587` | SMTP port |
| `SMTP_USERNAME` | — | SMTP username |
| `SMTP_PASSWORD` | — | SMTP password |
| `LIVEKIT_URL` | — | LiveKit server URL (only for the Room tool) |
| `LIVEKIT_API_KEY` | — | LiveKit API key |
| `LIVEKIT_API_SECRET` | — | LiveKit API secret |

Email sending requires SMTP configuration. Without it, all other features work fine — invitation and notification emails just won't be sent.

LiveKit is only needed for the Room (video) tool. All other tools work without it.

### Once

Dobase is compatible with [Once](https://once.com) by 37signals. Point Once at `ghcr.io/smgdkngt/dobase:latest` and it handles the rest.

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

### Commands

```bash
bin/dev                    # Start dev server (Rails + Tailwind watcher)
bin/rails test             # Run tests
bin/rails test:system      # Run system tests
bin/rubocop                # Lint Ruby
bin/brakeman --quiet       # Security analysis
```

## Deployment with Kamal

For production deployments with SSL and zero-downtime deploys, Dobase ships with [Kamal](https://kamal-deploy.org) support.

Edit `config/deploy.yml` with your server IP and domain, add secrets to `.kamal/secrets`:

```bash
# .kamal/secrets
SECRET_KEY_BASE=<generate with: bin/rails secret>
SMTP_USERNAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password
```

Then deploy:

```bash
kamal setup    # First deploy
kamal deploy   # Subsequent deploys
```

## License

[O'Saasy License](LICENSE.md) — MIT-style with SaaS restriction. Free to use, modify, and self-host. Cannot be offered as a competing hosted service.
