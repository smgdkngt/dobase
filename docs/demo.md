# Running a public demo

With `DEMO_MODE=true`, an installation becomes a public demo. The sign-in page gets a
**Try the demo** button. A visitor who presses it is signed in on the spot, without an
account or an email address, to a workspace of their own: Moonshot Snacks, the same
example company that `SEED_DEMO=1 bin/rails db:seed` makes, with a board, a chat, todos,
docs, files, a room, a mailbox and a calendar, shared with three made-up teammates.

Run the demo as its own app with its own database, never on an installation people use
for real work.

## What the demo switches off

Everything that reaches outside the app:

- **Email.** Nothing is sent: no invitations, notification digests or password resets
  (`action_mailer.perform_deliveries` is off). No SMTP settings are needed.
- **Mail.** The mailbox is example data. Connecting a mail account, sending mail, syncing
  and making folders on the server are refused. Reading, starring, archiving, trashing
  and saving drafts work, locally.
- **Calendar.** Connecting a CalDAV account and syncing are refused. Local calendars work.
- **Public links.** Files and folders can't be shared by link.
- **Invitations.** Nobody can be invited to a tool.
- **Signing up.** Visitors don't need an account, so registration is closed.
- **Uploads** are 10 MB at most, per file.

Refused actions answer with "That's switched off in the demo." (JSON: `403` with
`{ "error": "Not available in the demo" }`). The jobs that talk to mail and calendar
servers are never queued, and those servers are refused even if something tried.

Visitors can make API access tokens and use the API and the `dobase` CLI.

## Cleanup

`Demo::CleanupJob` runs every hour (`config/recurring.yml`) and removes visitors who came
more than a day ago, with all their tools and files. A visitor's page says so in a banner
along the bottom. The teammates stay; they're shared by every workspace.

## Video rooms

The Room tool needs LiveKit like any installation. To share a LiveKit server with
another installation, give the demo a room prefix so its rooms never meet the other's:

```
LIVEKIT_ROOM_PREFIX=demo-
```

Without LiveKit the demo's room says video isn't set up; the rest works.

## Deploying with Kamal

Deploy the demo as a separate Kamal destination with its own service name and volume,
so it has its own container and database. For example `config/deploy.demo.yml`:

```yaml
service: dobase-demo

servers:
  web:
    - your-server-ip

proxy:
  ssl: true
  host: demo.example.com

env:
  secret:
    - SECRET_KEY_BASE
    - LIVEKIT_API_KEY
    - LIVEKIT_API_SECRET
  clear:
    SOLID_QUEUE_IN_PUMA: true
    DEMO_MODE: true
    APP_HOST: demo.example.com
    LIVEKIT_URL: wss://room.example.com
    LIVEKIT_ROOM_PREFIX: demo-

volumes:
  - "dobase_demo_storage:/rails/storage"
```

Put its secrets in `.kamal/secrets.demo`, then:

```bash
kamal setup -d demo    # first deploy
kamal deploy -d demo   # after that
```

The first start creates the database and the tool types; the first visitor creates the
teammates. There's nothing else to set up.
