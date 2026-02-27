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

## Getting Started

### Requirements

- Ruby 3.2.5
- SQLite 3
- libvips (for image processing)

### Setup

```bash
git clone https://github.com/your-org/dobase.git
cd dobase
bin/setup
```

This installs dependencies, prepares the database, seeds tool types, and starts the dev server.

Or start manually:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

The app runs at `http://localhost:3000`. Sign up to create your first account.

### Docker

```bash
docker compose up
```

This starts the app with a pre-built image. Visit `http://localhost:3000`.

For production deployment, see the `Dockerfile` and `config/deploy.yml` (Kamal).

## Configuration

All branding is configurable via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `APP_NAME` | `Dobase` | App name in UI, emails, page titles |
| `APP_LOGO_PATH` | `/icon.svg` | Logo path (sidebar, auth pages, mobile header) |
| `APP_HOST` | `localhost:3000` | Host for mailer URLs |
| `APP_FROM_EMAIL` | `notifications@dobase.co` | Sender address for notification emails |

### Optional Services

- **SMTP** — Required for sending notification and invitation emails. In development, emails open in the browser via `letter_opener`. For production, set `SMTP_*` environment variables (see [Deployment](#2-set-up-secrets)).
- **LiveKit** — Required only for the Room (video) tool. Without it, all other tools work fine.

## Architecture

### Tool System

Every feature is a **Tool** instance linked to a **ToolType**. Users add tools to their workspace and optionally share them with collaborators. Permissions are binary: **owner** (full control) or **collaborator** (functional access).

### Stack

- **Backend**: Rails 8.1, SQLite, Solid Queue (background jobs), Solid Cable (WebSockets)
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS v4, Rhino Editor (rich text)
- **Real-time**: ActionCable for chat, notifications, collaborative editing, and presence
- **Auth**: Session-based with `has_secure_password`
- **Deployment**: Docker + Kamal

## Deployment

Dobase ships with [Kamal](https://kamal-deploy.org) for zero-downtime Docker deployments to any server.

### 1. Configure your server

All you need is a simple VPS with Ubuntu installed. Kamal handles the rest (Docker, SSL, zero-downtime deploys). Make sure to enable a firewall (allow 22, 80, 443 — plus [LiveKit ports](https://docs.livekit.io/home/self-hosting/ports-firewall/) if using video), enable unattended security updates, and use SSH key authentication (disable password auth).

Edit `config/deploy.yml` — set your server IP and domain:

```yaml
service: dobase
image: dobase

servers:
  web:
    - your-server-ip

proxy:
  ssl: true
  host: your-domain.com

registry:
  server: localhost:5555
```

### 2. Set up secrets

Generate a secret key base and add your credentials to `.kamal/secrets` (this file is gitignored):

```bash
bin/rails secret  # generates a SECRET_KEY_BASE value
```

```bash
# .kamal/secrets
SECRET_KEY_BASE=your-generated-secret

# Required for sending notification/invitation emails
SMTP_USERNAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password

# Optional — only needed for the Room (video) tool
LIVEKIT_API_KEY=your-key
LIVEKIT_API_SECRET=your-secret
```

Non-sensitive settings (SMTP address/port, app name, etc.) are configured in `config/deploy.yml` under `env/clear`.

### 3. Deploy

```bash
kamal setup    # First deploy: provisions server, builds image, starts app
kamal deploy   # Subsequent deploys
```

Kamal handles SSL certificates (Let's Encrypt), zero-downtime deploys, and asset bridging automatically.

### Useful aliases

```bash
bin/kamal console  # Rails console on server
bin/kamal logs     # Tail production logs
bin/kamal shell    # SSH into app container
```

### Storage

SQLite database and Active Storage files live in a persistent Docker volume. Back up `/rails/storage` on your server regularly.

## Development

```bash
bin/dev                    # Start dev server (Rails + Tailwind watcher)
bin/rails test             # Run tests (Minitest)
bin/rails test:system      # Run system tests (Capybara + Selenium)
bin/rubocop                # Lint Ruby
bin/brakeman --quiet       # Security analysis
```

## License

[O'Saasy License](LICENSE.md) — MIT-style with SaaS restriction. Free to use, modify, and self-host. Cannot be offered as a competing hosted service.
