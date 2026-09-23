# Running a public demo

With `DEMO_MODE=true`, an installation becomes a public demo. The sign-in page gets a
**Try the demo** button. A visitor who presses it is signed in on the spot, without an
account or an email address, to a workspace of their own: Moonshot Snacks, the same
example company that `SEED_DEMO=1 bin/rails db:seed` makes, with a board, a chat, todos,
docs, files, a room, a mailbox and a calendar, shared with three made-up teammates of
their own.

Run the demo as its own app with its own database, never on an installation people use
for real work.

## Teammates

Every visitor gets their own Marcus, Priya and Jake (`Demo.create_visitor!`), known by
the key in their addresses: `visitor-<key>@visitors.demo.invalid` and
`marcus-<key>@team.demo.invalid` (`Demo.party_of`, `Demo.teammates_of`).

**They do things by themselves.** For about two minutes after a visitor arrives,
`Demo::TeammatesJob` plays a short script: Marcus turns up in Team Chat, types and says
hello, Priya opens a card on Product Launch and comments on it, Jake hands the visitor a
new todo, and Marcus comes back to suggest trying it together. It goes through the
models like anyone would, so the messages, the mentions and the assignment arrive live
with their notifications, and the teammates' faces show on the tools they're in. A step
whose card, tool or visitor is gone is skipped; a teammate someone has joined as is left
to them.

**Try it together.** The banner links to join as each teammate (signed, expiring with
the demo). Opened in a private window, on another device or by a friend, the link signs
that window in as the teammate, and the two see each other type, chat and call live.
Only a demo teammate can be joined as this way, never a visitor or an account. Teammates
are demo users like visitors, with the same limits.

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
- **Uploads** are off: files, attachments, chat files, avatars and images pasted into docs. The example workspace brings its own files.

Refused actions answer with "That's switched off in the demo." (JSON: `403` with
`{ "error": "Not available in the demo" }`). The jobs that talk to mail and calendar
servers are never queued, and those servers are refused even if something tried.

## What keeps it small

- **No API tokens.** Visitors can't make access tokens, so the demo can't be scripted
  through the API.
- **60 changes a minute** per visitor (or per address, when signed out), across the whole
  app. More gets "You're going a bit fast for the demo" (JSON: `429`).
- **5 new demos per address** every 10 minutes, and at most 500 visitors at once
  (`Demo::MAX_VISITORS`). After that the sign-in page says the demo is busy.
- **30 tools per visitor** (`Demo::MAX_TOOLS_PER_VISITOR`).
- **A storage budget.** Once the database passes 2 GB (`Demo::STORAGE_BUDGET`), the demo
  takes no more changes, over HTTP or in shared documents, until the cleanup has made
  room; deleting and signing out still work. This keeps a demo on a shared server from
  filling the disk, whatever a script finds to write.
- **Limit request bodies** at the proxy too (see the deploy example below), since text
  fields have no length limit of their own.

## Cleanup

`Demo::CleanupJob` runs every hour (`config/recurring.yml`) and removes visitors who came
more than a day ago, with their teammates and all their tools and files. A visitor's page
says so in a banner along the bottom.

## Video rooms

The Room tool needs LiveKit like any installation. To share a LiveKit server with
another installation, give the demo a room prefix so its rooms never meet the other's:

```
LIVEKIT_ROOM_PREFIX=demo-
```

Without LiveKit the demo's room says video isn't set up; the rest works. Sharing a
LiveKit server is cheap: invitations are off, so a room holds at most a visitor and the
few people they asked over with a teammate link.

## Deploying with Kamal

Deploy the demo as a separate Kamal destination with its own service name and volume,
so it has its own container and database. For example `config/deploy.demo.yml`:

```yaml
service: dobase-demo

servers:
  web:
    hosts:
      - your-server-ip
    # On a server that also runs a real installation, keep the demo within bounds
    options:
      memory: 1g
      cpus: 1

proxy:
  ssl: true
  host: demo.example.com
  buffering:
    max_request_body: 512_000

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

The first start creates the database and the tool types; each visitor brings their own
teammates. There's nothing else to set up.

### Keeping the demo on the same version

A Kamal `post-deploy` hook can make the demo follow every deploy of your real
installation. Kamal wants an image labelled with the demo's own service name, so the
demo builds its own; the build cache the real deploy just filled makes that quick.
A demo that fails to follow doesn't fail the deploy. In `.kamal/hooks/post-deploy`
(with `production` being your destination):

```sh
#!/bin/sh
if [ "$KAMAL_DESTINATION" = "production" ] && [ -f config/deploy.demo.yml ]; then
  kamal deploy -d demo --skip-hooks ||
    echo "WARNING: the demo did not follow; run: kamal deploy -d demo"
fi
```

Why not a role in the same deploy file? Roles share the volumes and secrets of
the service, so the demo would share the real installation's database, files and
`SECRET_KEY_BASE`, and a demo that fails to boot would stop the real deploy.

