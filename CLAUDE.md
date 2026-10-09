# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Dobase** is a Ruby on Rails 8.1 app that provides user-installable "tools" inside a single workspace. Users add tool instances (boards, chat, mail, files, docs, calendar, room, todos), each optionally shared with collaborators.

### Branding / Configuration

All branding is configurable via environment variables (defaults to "Dobase"):

| Variable | Default | Purpose |
|----------|---------|---------|
| `APP_NAME` | `Dobase` | App name shown in UI, emails, page titles |
| `APP_LOGO_PATH` | `/icon.svg` | Path to logo image (sidebar, auth pages) |
| `APP_HOST` | `localhost:3000` | Host for mailer URLs (production) |
| `APP_FROM_EMAIL` | `notifications@dobase.co` | Sender address for emails |
| `DEMO_MODE` | — | `true` makes a public demo (`Demo`, `docs/demo.md`): throwaway visitor workspaces, and whatever reaches outside the app refused via `restrict_in_demo` / `skip_in_demo` |

Config lives in `config/initializers/app_config.rb`. View helpers: `app_name`, `app_logo_path`.

Mail (IMAP/SMTP) and calendar (CalDAV) connections go through `RemoteHost.verify!`, which refuses hosts that resolve to local addresses, and private networks unless `ALLOW_PRIVATE_NETWORK_HOSTS=true`. Tests use a fake resolver (`test/test_helper.rb`): names are public, `localhost` is local, `*.internal` is private, `*.invalid` doesn't resolve.

## Development Commands

```bash
bin/dev                    # Start dev server (Rails + Tailwind watcher via foreman)
bin/setup                  # Install deps + prepare DB (--reset to drop/recreate)
bin/rails test             # Run unit/integration tests (Minitest)
bin/rails test:system      # Run system tests (Capybara + Selenium, needs Google Chrome)
bin/system-test            # Same tests with cached Chrome for Testing (no Google Chrome needed)
bin/rails test test/models/tool_test.rb           # Run single test file
bin/rails test test/models/tool_test.rb:42        # Run single test at line
bin/rubocop                # Lint Ruby (rubocop-rails-omakase)
bin/brakeman --quiet       # Security static analysis
bin/ci                     # Full CI pipeline (setup, lint, audit, tests, seeds)
npm test                   # JavaScript tests (Node's own runner, no browser); `npm ci` once first
npm run check              # Type checks of the scripts listed in tsconfig.json
bin/screenshots take before   # A picture of every scene; `compare before after` says what a change did
```

## Deployment

```bash
kamal deploy -d dobase     # Deploy to production (requires -d dobase destination flag)
kamal console -d dobase    # Rails console on production
kamal logs -d dobase       # Tail production logs
```

The `config/deploy.yml` contains open-source placeholder values. Real production config lives in `config/deploy.dobase.yml` (the Kamal destination file). Always use `-d dobase` when deploying.

Docker images are published to `ghcr.io/smgdkngt/dobase` via `.github/workflows/publish-image.yml` on push to main and CalVer tags (e.g., `2026.04.07`), for amd64 and arm64. Compatible with [ONCE](https://github.com/basecamp/once) by 37signals.

The image is one container that does everything: it sets `SOLID_QUEUE_IN_PUMA=true` itself, so a plain `docker run`, the compose file and ONCE all run background jobs (without them mail never syncs or sends). What ONCE hands an installation is used when Dobase's own variable is unset: `BASE_URL` for the links in mail (`APP_HOST`), `MAILER_FROM_ADDRESS` for the sender (`APP_FROM_EMAIL`), and `SMTP_*`, `SECRET_KEY_BASE` and `DISABLE_SSL` under the same names. A new installation has no users, so its sign-in page goes to sign-up. To try an install method: build the image (`docker build -t dobase-test .`) and run it as the README says; for ONCE push it to a local registry and `once deploy` it with `--disable-tls` under a `*.localhost` hostname.

**Tailwind CSS** must be rebuilt after stylesheet changes:
```bash
bin/rails tailwindcss:build   # writes app/assets/builds/tailwind.css, which the layout loads
```
The `bin/dev` watcher handles this automatically in development.

## Architecture

### Tool System

Every feature is a **Tool** instance linked to a **ToolType** (slug: `mail`, `boards`, `files`, `chat`, `docs`, `calendar`, `room`, `todos`). `ToolsController#show` redirects to the tool-specific controller based on slug.

**Permissions are binary.** Checked via `ToolAuthorization` concern (`can_access?` / `can_manage?`). Access is tracked in the `collaborators` table with a `role` column:
- **Owner** (`role: "owner"`) — full control, can invite/remove collaborators, promote to owner, rename, delete. Tools can have multiple owners.
- **Collaborator** (`role: "collaborator"`) — full functional access within the tool, cannot delete or re-share

The tool creator is automatically added as an owner collaborator (`after_create :add_creator_as_owner`). Check ownership via `tool.owned_by?(user)` and access via `tool.accessible_by?(user)` — both query the collaborators table. Permissions are explicit and instance-based — never inferred.

Controllers under `/tools/:tool_id` include the `ToolScoped` concern, which loads `@tool` from `params[:tool_id]` and authorizes access. Only controllers that load their tool differently (from a card, a list, another param) or need owner rights wire that up themselves.

### Namespacing Pattern

Models and controllers are namespaced per tool. Models set `self.table_name` explicitly:

```ruby
module Boards
  class Card < ApplicationRecord
    self.table_name = "cards"
  end
end
```

Controllers nest under `Tools::`:
```
app/controllers/tools/boards/cards_controller.rb  → Tools::Boards::CardsController
app/controllers/tools/chats/messages_controller.rb → Tools::Chats::MessagesController
```

### RESTful Controllers (Strict)

**Only standard CRUD actions (index, show, new, create, edit, update, destroy).** Non-RESTful actions are forbidden:

```ruby
# BAD - god controller with custom actions
class BoardsController
  def create_column
  def update_column
  def reorder_cards
end

# GOOD - separate controllers for each resource
class BoardColumnsController  # index, create, update, destroy
class BoardCardsController    # show, create, update, destroy
class BoardCardPositionsController  # update (for reordering)
```

State changes get dedicated controllers:
```ruby
# Instead of: patch :toggle_read, patch :toggle_starred
class EmailReadsController     # create/destroy (mark read/unread)
class EmailStarsController     # create/destroy (star/unstar)
class EmailArchivesController  # create/destroy (archive/unarchive)
class EmailTrashesController   # create/destroy (trash/restore)
```

### Routes

`scope module:` for namespacing without URL bloat:
```ruby
resources :tools do
  scope module: :tools do
    resource :board, only: :show do
      scope module: :boards do
        resources :columns
        resources :cards
      end
    end
  end
end

# Top-level resources for simpler URLs (IDs are globally unique)
resources :cards do
  scope module: :cards do
    resources :comments
    resources :attachments
  end
end
```

### JSON API & CLI

The API is the web app answering JSON: same routes and controllers, `respond_to` with `format.json` and jbuilder views next to the HTML ones. Docs live in `docs/api/`; keep them in sync when changing an endpoint.

- **Auth**: personal access tokens (`AccessToken`, created under Profile → API, SHA-256 digest stored). `Authorization: Bearer` requests authenticate by token only, skip CSRF, and don't touch `last_visited_path`/`last_seen_at`. `Current.user` works for both sessions and tokens.
- **Opt-in per controller**: token requests get `403` unless the action calls `allow_access_tokens` (optionally `only:`/`except:`). Never allow tokens on account, credential (mail/calendar accounts), sharing/collaborator or whole-tool deletion actions, or on anything that deletes data outside Dobase (emptying the trash, deleting mail for good). Tokens trash mail only where that is a move: an account whose server has a trash folder (`server_trash?`), else `422`.
- **Read tokens** may only `GET`/`HEAD`.
- **Posting as an agent**: chat messages and card/todo comments remember the token that posted them (`PostedVia`: `via` = token name, `agent`). The owner stays `user`; an agent token (`access_tokens.agent`) shows under its own name ("Claude for Sem", bot avatar) and counts as unread/notifies its owner. Render names with `shared/posted_by` / `poster_name`.
- **Conventions**: create → `render :show, status: :created`; update/state change → `render :show`; destroy → `head :no_content`; validation errors → `{ errors: full_messages }` (422); other errors → `{ error: "..." }`. Unauthenticated JSON → 401, `RecordNotFound` → 404 JSON, denied tool access → 403 JSON. Rich text renders through `shared/rich_text` (plain + `_html`), users through `users/user`/`users/optional_user`. GET JSON must not mark things read.
- **Gotcha**: `wrap_parameters` is on for JSON — a flat param named like the controller's singular (e.g. `position` in a `PositionsController`) gets wrapped; use `wrap_parameters false`.
- **Tests**: `api_headers(user, permission:)` from `test/test_helpers/api_test_helper.rb`; API tests live in `test/controllers/**/*_api_test.rb`.

`cli/` holds the `dobase` command-line client (Go, standard library plus `golang.org/x/term` and tcell; one binary per platform, cross-compiled and attached to every GitHub release by `.github/workflows/cli-release.yml`; `cli/install.sh` downloads it) and its Claude Code skill (`cli/SKILL.md`). Commands are declared per noun in `cli/internal/commands/*.go` with `New("noun verb", summary, []string{ARGS}, []Flag{flags}, function)`; `dobase help` is generated from those. API responses are `api.Value` (ordered JSON: `.Get("a", "b").S()`, missing reads as empty), so `--json` prints what the server sent. `dobase` without arguments in a terminal opens a full-screen app (`cli/internal/tui/`, tcell): a screen per tool type, network work queued as jobs so a spinner shows first, live screens refreshed every 10s on a background goroutine (stale results dropped), undo on `u`, tests drive it by key presses against a fake API on a simulated screen. `go test ./...` in `cli/` checks every command and that the examples in `cli/SKILL.md` and the READMEs exist; the CI `cli` job runs it with `go vet` and `gofmt`. `dobase app install` makes Dobase an app of its own (`cli/internal/command/app.go`, `electron.go`): Electron started on the scripts in `cli/internal/command/shell/` (embedded in the binary; `main.js` is the app, `links.js` says which addresses are the server's, `preload.js` marks the page `html[data-app-window]`). On a Mac it downloads Electron's zip, renames the bundle (`co.dobase.app`, the manifest's name and icon) into `~/Applications` and signs it ad hoc; on Linux it uses the system's `electron` or downloads one, and writes a desktop entry. The server's pages stay in the app's windows, every other address goes to the system's browser, and a link from `--open` reaches a running app as `web+dobase://path`. Electron brings no browser interface, so what a browser does by itself is in `main.js`: permissions, the menu under the right mouse button, the question before leaving unfinished work. The Go tests build Electron's zips themselves and serve them from a fake release server; `test/javascript/app_shell.test.mjs` checks `links.js`. Nothing in CI runs a real Electron: after changing `shell/`, install into a scratch `HOME` (not under `/tmp`: macOS refuses notifications from an app there) against `demo.dobase.co` and try it. An app bundle run from `/tmp` or signed again asks for its permissions anew. `app_earlier.go` only removes the first kind of app (a web app in a browser profile, which a Mac took for the browser itself). When adding an endpoint the CLI should use, add the command, update `cli/SKILL.md` if it changes how an agent should behave, and smoke-test against `bin/dev` with `DOBASE_URL`/`DOBASE_TOKEN` (`go run . ...`).

### Real-time (ActionCable)

- **ChatChannel** — messaging, typing indicators, presence
- **DocumentSyncChannel** — shared Yjs editing of a document: stores and relays updates (`Docs::Update`), relays cursors (awareness), and marks the document "open" (`locked_by`) for the documents list and the API. A write from outside the editor throws that copy away (`Docs::Document#reset_shared_copy!` bumps `shared_copy_generation`): changes to an older copy are refused and open editors load the document again. The vendored rhino-editor bundle carries the Collaboration extensions; see `vendor/javascript/README.md`
- **DocumentChannel** — read-only viewers of a document: saved content and whether someone has it open
- **PresenceChannel** — who is in a tool and what they have open (`presence:context` events, `data-presence-item`/`data-presence-target` in views), plus comment typing, and that something in the tool changed (below). Nothing stored: pages announce every 30s and forget anyone quiet for 90s. **WorkspacePresenceChannel** listens to every shared tool for the sidebar faces
- **NotificationChannel** — per-user stream (`notifications:#{user.id}`) for real-time notification delivery, and for what a person's other pages should know: a theme picked, mail read, the workspace's tiles arranged in another browser
- Action Cable only passes the payload to an action with exactly one required argument (`def announce(data)`), and `transmit` needs a braced hash
- Connection authenticates via signed session cookie

### A page that shows what changes (live updates)

A tool's page shows what changes in the tool while it is open, whoever did it and from where: another window, a colleague, the API or the CLI. **A board, a todo list, a files tool, the documents list, the calendar's week and a mailbox do** (`ApplicationHelper::LIVE_PAGES`, by controller and action: the pages that show what is in a tool, never a form, an open document or a mail that is being written, which is `tools/mails#new`). Chat and an open document keep their own, finer way.

- **The server only says that something changed, never what.** `AnnouncesChanges` (in `ApplicationController`) is the one place: after every request that isn't a GET, went well and was let into a tool, `Tool#announce_change` sends `{ type: "changed", tool_id:, by: }` on the stream the tool's pages already listen to (`PresenceChannel`, so no new connection or subscription, and nobody hears of a tool they can't open). The page then asks for itself again, which is an ordinary request with the ordinary checks. Not from the models: a card or a todo is moved with `update_all` in six places, which skips their callbacks, and one request commits several times.
- **An action whose change is nobody else's to see** says `announces_no_change :create` (a tool marked as seen, a chat read; chat messages, which their own stream shows), or `announce_no_change` while it runs (a column folded away for yourself). `test/integration/changes_announced_test.rb` lists every one with its reason and fails on one that isn't listed; for the kinds of tool that listen it also tries every action that writes, and fails on one it doesn't try.
- **What changes a tool without a request** (a job, a sync) calls `tool.announce_change` itself: `SyncCalendarsJob` and `SyncEmailsJob` do when the sync brought something the page shows (they compare before and after) and not otherwise, `SendMailJob` when mail has gone out or is a draft again, `PurgeTrashedMailJob` when it emptied a trash. A change made in the console is announced to nobody.
- **A look that changes something** says `announce_a_change`: mail is read by opening it, and is read in every window then. Reading through the API changes nothing and says nothing.
- **The page** (`live_controller.js`, on `<main>` and on a tile's `.tile-page` through `main_attributes`) hears it from `presence_controller.js` as `presence:changed` and draws itself again with `visitPage` (`services/tile.js`): a morph, in a document of its own and in a tile of the workspace's page alike. When it does is `services/live.js` (tested in `test/javascript/live.test.mjs`): a moment after the first change so a row of them is one drawing, at most every second and a half, and **never while the page is in use**: a dialog, a menu or the gallery open (`pageInUse`), the cursor in a field, a field in sight holding text that wasn't sent (`unsentText`), something held with the pointer, or a window nobody looks at. What a page keeps in the browser only and a drawing would lose, it marks with `data-live-busy` for as long as it is there: the files that are picked, the files' own menu, the mail that is ticked. It stays behind then and looks again every second. A dialog opened between asking and drawing holds the drawing back too (`hold`).
- **The page that made the change doesn't draw it twice.** Turbo gives its requests an id and keeps them (`Turbo.session.recentRequests`), `services/api.js` and the files page send their own through `Turbo.fetch` for that (a plain `fetch` has no id, and its page draws the change a second time), and the announcement carries the id (`by`). Tiles in the workspace's own page are one document: there the change is the tile's you are in, and another tile of the same tool draws it.
- After the line was down (a laptop that slept) a page draws itself once: what changed meanwhile was announced to nobody there.
- The mailbox still asks for a sync every minute and draws itself after asking (`mail_refresh_controller.js`), as it did before any of this. What the sync brought arrives when the sync is done, by the announcement.
- A new page: add it to `LIVE_PAGES`, see what it keeps in the browser only (a selection, a filter that isn't in the address) and mark that `data-live-busy` or make it survive a morph, send its own requests through `Turbo.fetch`, and add its tests to `test/system/live_updates_test.rb` (a change through the API with a token, the open page shows it without being loaded again) and its actions to the coverage test.

### Rich Text (ActionText + Rhino Editor)

Rhino Editor (TipTap-based) replaces Trix. Two editor modes:
- **Full** (Docs): `.document-editor` / `.document-view` classes, large text, full toolbar
- **Compact** (Chat/Comments): `.rich-text-input` wrapper, pruned toolbar (bold/italic/link/code), inherits font size from context

Models use `has_rich_text :body`. The `rich_text_input` component wraps `rich_text_area_tag` with a Stimulus controller for enter-to-submit and toolbar pruning. Rhino Editor toolbar is in shadow DOM — style via `::part(toolbar)`, `::part(editor-wrapper)`. The shared Rhino theme (the `--rhino-*` variables and `::part(toolbar__button)` styles for every editor) lives in `components.css`.

### Background Jobs

Solid Queue (database-backed). Recurring jobs defined in `config/recurring.yml`:
- `SyncAllEmailsJob` — every 5 minutes, syncs all mail accounts
- `SyncAllCalendarsJob` — every 15 minutes, syncs all CalDAV accounts
- `NotificationDigestJob` — every hour, sends digest emails to users with unread notifications

Key jobs: `ImapSyncJob` (individual IMAP actions), `SyncEmailsJob`, `SyncCalendarsJob`, `PushEventJob` (CalDAV push), `SyncDraftJob` (draft IMAP sync).

### Notifications (Noticed gem)

In-app + optional email notifications via `noticed` gem. Notifiers live in `app/notifiers/` and extend `Noticed::Event`:

```ruby
class CardAssignmentNotifier < Noticed::Event
  required_params :card, :assigner, :tool

  deliver_by :custom_action_cable,
    class: "Noticed::DeliveryMethods::CustomActionCable",
    stream: -> { "notifications:#{recipient.id}" },
    message: -> { notification_data }

  deliver_by :email, mailer: "NotificationMailer", method: :card_assigned

  notification_methods do
    def message
      "#{event.params[:assigner]&.name || 'Someone'} assigned you to #{event.params[:card]&.title || 'a card'}"
    end
    def url ...
    def icon_name ...
  end
end
```

Fire from controllers/callbacks: `CardAssignmentNotifier.with(card: card, assigner: user, tool: tool).deliver(recipient)`

**Notifiers**: `ToolInvitationNotifier`, `ChatMessageNotifier`, `CardCommentNotifier`, `CardAssignmentNotifier`, `CardMovedNotifier`, `TodoAssignmentNotifier`, `TodoCommentNotifier`, `TodoCompletedNotifier`, `FileUploadedNotifier`, `DocumentCreatedNotifier`, `CalendarEventCreatedNotifier`. All param access must be nil-safe (`&.name`, `&.title`) since referenced records can be deleted: `config/initializers/noticed.rb` makes only the deleted record read as nil (Noticed alone drops every param when one is gone). All notifiers include `tool_id` in their `notification_data` payload for real-time sidebar activity dots.

**UI**: Bell icon in sidebar with unread badge. Popover loads notification list via Turbo Frame. Stimulus `notifications_controller` subscribes to ActionCable for real-time badge updates. Sidebar tool items show an **activity dot** (`data-unread` attribute) when a tool has new content since the user's last visit — tracked via `collaborators.last_seen_at`, touched by `ApplicationController#track_last_visited_path`. Bulk detection uses `Tool.unread_tool_ids_for(user)`. Real-time dots are pushed via `tool_id` in notification payloads.

### Invitations & Collaboration

Collaborators are always added via invitation (never direct-add). Flow:
1. Owner sends invitation → `CollaboratorMailer#invitation` email + `ToolInvitationNotifier` (if user exists)
2. Recipient visits acceptance link → `InvitationAcceptancesController#show` (confirmation page)
3. Accept (POST) creates collaborator record, Decline (DELETE) marks invitation as declined
4. Unauthenticated users are redirected to login/signup with return-to session tokens

`Invitation` model: auto-generates token, 7-day expiry, statuses: `pending`/`accepted`/`declined`. Declined invitations show in collaborators panel with a "Reinvite" option.

### Themes

`Theme` (`app/models/theme.rb`) turns a palette in Omarchy's `colors.toml` names into the `--color-*` tokens of `tokens.css`, nudging text, the accent and button fills until they carry WCAG AA. The built-in themes are Omarchy's (`config/themes.yml`); a user has `theme_name` and, for a palette of their own, `theme_colors` (`User#theme`, `User#choose_theme`). No theme means the app's own look, light or dark by `prefers-color-scheme`.

- The layout puts a theme on `<html>` as an inline `style` plus `data-theme`, `data-theme-mode` and `data-theme-version` (`theme_attributes`). Turbo never touches `<html>`, so a change goes through `services/theme.js`: pushed as `type: "theme"` on the notification stream, and `theme_controller` on `<body>` fetches `/appearance` when the body's version isn't the one `<html>` wears.
- **One theme, or one for light and one for dark** (`users.theme_follows_system`, `dark_theme_name`; `User#theme(scheme)`, `choose_theme(name, colors, scheme:)`, `follow_system`). Only the browser knows whether its system is light or dark, so `services/theme.js` keeps a `scheme` cookie (`browser_scheme` on the server draws the page by it), `<html>` says `data-theme-follows-system`, and when the system changes over the page asks `/appearance` again. A push on the notification stream then carries no theme: every page asks for its own. A theme set without a scheme (the CLI) is one theme again.
- `AppearancesController` (`resource :appearance`, HTML and JSON, tokens allowed: it is cosmetic) is what the profile's Appearance tab and `dobase theme set|sync|follow` talk to. In the tab a pick is put on in place (`appearance_controller.js`), so the dialog it is in stays; without scripts the form goes to the profile page. `dobase theme follow` installs an Omarchy `theme-set` hook.
- A theme reaches everything: the label hues (`--color-label-*`: tool type icons, faces without a picture), the logo (`shared/logo`, drawn inline in `--color-logo`), native controls (`accent-color`), selection and scrollbars. Pages with nobody signed in (sign-in, shared links, the manifest) use the theme the browser last had, kept in a signed `theme` cookie (`remember_theme`, `remembered_theme`); the offline page reads a few colours from `localStorage`. Cmd+K offers every theme once you type towards one.
- The typeface is a setting of its own (`users.typeface`, `"mono"` or nil, `data-typeface` on `<html>`): mono points `--font-family-sans` at the monospace stack, which ends in the generic `monospace` and names no font a Linux desktop has, so on Omarchy it is the desktop's font (fontconfig). `--font-family-ui` is always the app's own.
- Mail the app sends wears the reader's theme and typeface too: `MailerHelper` looks the recipient up by address (`mail_reader`) and gives every mailer view its colours through `mail_color(:text)` and `mail_font`, never a hex in a view. Without a theme the mail keeps the app's own look, with the dark set in the layout's `<style>`. The logo in a themed mail is `/logos/<fill>-<ink>.png` (`LogosController`: the shipped PNG recoloured, open to anyone, since libvips' SVG loader is blocked).
- **Except a colour someone picks to know a thing by**: a card's colour (`--color-card-*` in `tokens.css`, `BoardsHelper::CARD_COLORS`) is the same in every theme, with a tint of its own for text on a light and on a dark page. `Theme` sets none of those tokens (`test/helpers/boards_helper_test.rb`). A calendar's colour is the hex its server gave.
- Styling for a theme must come from tokens. What sits on an accent or danger fill is `text-text-inverse` (white or the theme's darkest colour), never `text-white`. Dark-only rules can't use `prefers-color-scheme` alone: add `:root[data-theme-mode="dark"]` (see `.email-frame`, `rhino-editor`).

### Avatars (Active Storage)

`User` model: `has_one_attached :avatar` with content type (PNG/JPEG/GIF/WebP) and size (5MB) validation. Displayed via `shared/avatar` partial with `variant(resize_to_fill: [200, 200])`. Requires `libvips` system library. Without a picture it is the initials in one of the theme's label colours over a shape in a second one, the same for the same person everywhere (`User#avatar_look`, `.avatar[data-avatar-hue]` in `components.css`; faces drawn in the browser get it through `services/avatar.js`).

### Email Tool (IMAP/SMTP)

All mail actions sync to the IMAP server: trash, archive, read/unread, star, move, delete. The `ImapSyncService` handles IMAP operations; controllers call `ImapSyncJob.perform_later` for async sync. The `archive_folder` setting on `Mails::Account` determines whether archiving moves to an IMAP folder or just marks as read.

A folder is kept and sent to the server by the server's name for it; what shows is `mail_folder_name`. Some servers (Dovecot and Courier on many hosts) keep every folder inside the inbox, as `INBOX.Receipts`: the folder sync learns that prefix from the server's NAMESPACE (`mail_accounts.folder_prefix`), the folder shows as Receipts (`Mails::Account#folder_without_prefix`, unless that is another folder's name), and a new folder is made under the prefix.

Mail drafts save locally and sync to the IMAP Drafts folder via `SyncDraftJob`. Files are attached to a saved draft through `Mails::DraftAttachmentsController` (the API and CLI's `--attach`). The server's trash folder is always `Trash` here, whatever the server calls it, and is not a folder to move to. A draft is trashed, moved and restored by itself, never with the conversation it answers; in the trash it stays `draft: true` (out of the `drafts` scope, shown as mail), and restoring puts it back in Drafts. The compose form uses `formaction` on the Save Draft button to submit to the drafts controller.

To, Cc and Bcc are fields of tokens (`tools/mails/_recipient_field`, `recipients_controller.js`, `tools/recipients.css`). The tokens in the page are what a field holds: the hidden field the form sends is written from them (`Ann Lee <ann@example.com>, joe@example.com`). A token moves by a drag (SortableJS, one group over the three fields, Cc and Bcc show while one is in the hand), by Shift and the arrows, or from its menu, which is the field's one popover. Text in and out of a field is `services/recipients.js` in the browser and `Mails::Recipient` on the server. The list under what is typed is a Turbo Frame that `Tools::Mails::ContactsController` fills (`Mails::RecipientSuggestions`: the people in Sent weighed by how lately, then contacts, then senders). Mail is kept by its addresses only, as synced mail is; names are looked up (`Mails::Account#names_for`: a contact's, else the one they sign with), for the tokens and for the headers of what goes out. A name typed with an address is remembered as a contact (`remember_names`).

A message in a conversation says who it went to (`tools/mails/_email_message`): closed, in one line of names; open, everyone in full under the sender, To, Cc and the Bcc of what was written here (`_message_recipients`). Those are text outside the button that opens and closes the message, so an address can be picked and copied. Their names are what is at hand (`Mails::Account#names_in`: a contact's, else how they sign in that conversation), because `names_for` reads all of the account's mail, which opening a mail can't wait for.

A reply or forward carries the mail it answers below its text, and that quote lives outside the compose editor (TipTap would flatten its layout): the draft names it (`quoted_message_id`) and `Mails::Quote` adds it when the mail goes out, when the draft is copied to the server and in the Sent copy. Unchanged, it is the mail as it was written. The compose page shows it in a frame that runs no scripts, whose text the page makes editable (`tools/mails/_compose_quote`, `compose_controller.js`): the form takes the quote from the frame the moment it is read, and what was changed is kept on the draft (`quote_html`, cleaned by `Mails::ReadableHtml`) and goes out instead. In the frame a picture shows by a `data:` address and says in `data-src` what it goes out as (`cid:quote-<id>@dobase`, or the remote address it isn't loaded from). The API takes and gives `quote_html`; the CLI has `--quote` and `--no-quote`. A reply that quotes nothing still says what it answers: the compose page has that mail under the text, closed and marked "Not sent along" (`tools/mails/_compose_answered`, found by the reply's `in_reply_to`). It is there to read; nothing in it is a field of the form, so it can't go out.

Sending from the compose page is asynchronous (`SendMailJob`). The draft becomes the mail in Sent at once (`Mails::Message#start_sending!`: `sending: true`, its final Message-ID), so it has left Drafts and shows in its conversation, which the page opens. The job sends that record (`sent_copy:`); refused mail is a draft again (`back_to_drafts!`) and the sender is notified. `mail_sending_controller` refreshes the page while a message is `sending`. The sync doesn't copy mail to the server's sent folder while it's `sending`. The JSON API sends synchronously.

**Important**: Never use `button_to` inside a `form_with` — it creates nested `<form>` tags which browsers break. Use `link_to` with `data-turbo-method` instead.

### Email Delivery

SMTP configured in `config/environments/production.rb` via env vars (`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`). Shared mailer layout in `app/views/layouts/mailer.html.erb`. Default from address uses `APP_FROM_EMAIL` env var.

The `app_name` helper is NOT available in mailer methods — use `Rails.application.config.x.app.name` directly. It IS available in mailer views via `helper :application`.

Notification URLs from notifiers return relative paths (`/tools/26/todo`). Use the `absolute_url` helper in mailer views to prepend `root_url`.

### Authentication

Session-based with `Current` (ActiveSupport::CurrentAttributes). `Current.user` available everywhere. Sessions stored in DB with IP/user-agent tracking. Optional TOTP two-factor authentication (`rotp` + `rqrcode` gems) — setup via `TwoFactorSetupsController`, challenge via `TwoFactorChallengesController`.

**Registration** is invite-only by default. Open when: no users exist (first setup), user has a pending invitation token, or `OPEN_REGISTRATION=true`. ALTCHA proof-of-work widget protects signup (skipped for first user). The widget loads as a standalone script in `public/altcha.min.js` — it cannot be imported via importmap due to its embedded web worker.

**SSL**: `config.force_ssl` and `config.assume_ssl` are disabled when `DISABLE_SSL=true` (ONCE sets this automatically on localhost). Session cookies do NOT set `secure:` explicitly — `force_ssl` controls this.

## Frontend

### Tailwind CSS Structure

```
app/assets/tailwind/
├── application.css    # Entry point, imports all others
├── tokens.css         # Design tokens (CSS custom properties for colors, spacing)
├── components.css     # Reusable component classes (.btn, .card, .modal-dialog, etc.)
├── layout.css         # Layout utilities
└── tools/             # Tool-specific styles (board.css, docs.css, etc.)
```

**Cascade layer note:** Tailwind v4 puts component styles in `@layer components`. Unlayered styles (Tailwind utility classes in ERB, Rhino Editor CSS) always beat `@layer components` rules regardless of specificity. This means:
- **Never use inline Tailwind utility classes on elements whose styles need to be overridden by `@layer components` CSS.** Instead, use semantic CSS classes (e.g., `.room-controls` instead of `flex items-center gap-2 px-4 py-3`) so that both the base style and mode-specific overrides live in the same layer and cascade normally.
- To override Rhino Editor specifically, use `!important` via Tailwind's `!` suffix (e.g., `border-none!`).

**Responsive breakpoint:** The sidebar hides at `<1024px` (`@media (max-width: 1023px)` in CSS, `max-lg:` in Tailwind utilities). Use `@media` blocks in CSS only for compound/child selectors (`.sidebar.open`, `.mail-layout > .mail-content`) that can't be expressed as Tailwind utilities. Use `max-lg:` prefix in ERB for simple single-element responsive styles.

**Popover positioning:** Popovers use the native Popover API with CSS Anchor Positioning. Always set `anchor-name` on the trigger, `position-anchor` and `position-area` on the popover:
```html
<button popovertarget="menu-id" style="anchor-name: --my-btn">
<div id="menu-id" popover="auto" class="popover-menu"
     style="position-anchor: --my-btn; position-area: block-end span-inline-start">
```

### Stimulus Controllers

Located in `app/javascript/controllers/`. Key ones: `board_controller`, `chat_controller`, `document_editor_controller`, `sortable_controller`, `modal_controller`, `popover_controller`, `rich_text_input_controller`, `notifications_controller`, `tabs_controller`.

**Never use class or ID selectors** to find DOM elements in Stimulus controllers. Always use Stimulus targets (`data-*-target`) or data attributes (`[data-item-name]`). Exception: when the target element lives outside the controller's DOM scope (e.g., modals rendered outside `<aside>` for stacking context), use `document.getElementById` instead. API calls go through `app/javascript/services/api.js` (includes CSRF token).

### Keyboard Shortcuts (`@github/hotkey`)

All keyboard shortcuts use the `@github/hotkey` library with **declarative `data-hotkey` attributes** on HTML elements. Every element with `data-hotkey` must also have `data-controller="hotkey"` — the `hotkey_controller` Stimulus controller calls `install()`/`uninstall()` on connect/disconnect, ensuring hotkeys are properly cleaned up during Turbo navigations.

```erb
<%# Visible button with hotkey %>
<%= render "components/button", text: "Compose", data: { controller: "hotkey", hotkey: "c" } %>

<%# Hidden trigger for stateful actions (e.g., j/k navigation) %>
<button data-controller="hotkey" data-hotkey="j" data-action="click->mail-keyboard#selectNext" hidden>Next</button>
```

- **`keyboard_shortcuts_controller`** lives on `<body>` — handles `?` to toggle the help dialog, Escape to close open dialogs, and opening the command palette
- **`hotkey_controller`** lives on each element with `data-hotkey` — manages install/uninstall lifecycle per-element
- **`command_palette_controller`** lives on the palette `<dialog>` — handles filtering, arrow-key navigation, Enter to jump/trigger actions
- **Help dialog**: `shared/_keyboard_shortcuts_dialog` renders global shortcuts + tool-specific sections via `content_for(:keyboard_shortcuts)` (rendered AFTER `yield` in layout so `content_for` blocks are captured)
- **Command palette** (`Cmd+K`): `shared/_command_palette` renders a searchable dialog with tool list + page-specific actions. Tool views define `content_for :command_palette_actions` blocks using `shared/command_palette_action` partials. Actions trigger the corresponding `data-hotkey` element when selected.
- **Tool-specific shortcuts**: Each tool view defines both `content_for :keyboard_shortcuts` (help dialog) and `content_for :command_palette_actions` (command palette) blocks
- **Platform modifiers**: Use `Mod+Key` (not `Control+Key`) for cross-platform shortcuts — maps to Cmd on Mac, Ctrl on Windows
- **Global shortcuts**: `?` help dialog, `Cmd+K` command palette, `b` notifications
- **Exception**: Document editor `Ctrl+S` stays in its controller since `@github/hotkey` skips contentEditable elements

### Tiling workspace (how a wide window works)

`/workspace` (`WorkspacesController`, `workspace_controller.js`, `workspace.css`) is the app in a window of 1024px and wider: no sidebar, every tool you open is a tile, and the tiles arrange themselves like a tiling window manager. A narrower window (a phone) gets the pages with the sidebar as a sheet and the bottom bar, one tool each. There is no choosing between the two.

- **A room's tile is the room's own page in an `<iframe name="workspace-tile">`** (every other kind of tool is a part of the workspace's page: the next section). What follows in this section about frames is about a room. The layout draws it without the sidebar, the notifications and the bottom bar when `tile?` (`ApplicationController`) is true: `Sec-Fetch-Dest: iframe` on the frame's first load, and the `X-Tile` header Turbo sends from inside the frame (`application.js`, which also marks `<html data-in-tile>` and asks again when the server didn't hear: plain HTTP, an old service worker). Its window is narrow, so a tool gets its **narrow-screen layout** by the media queries a phone uses, minus the bottom bar. No tool knows about tiles.
- A tile request touches `last_seen_at` but never `last_visited_path`, never stores a return-to address, and never gets the workspace itself. The service worker leaves frame navigations alone (fetched from there they lose `Sec-Fetch-Dest`); system tests switch the service worker off, so that path only shows in a real browser. CSP has `frame-ancestors 'self'`.
- **Where a window goes** is decided before the page is drawn by `workspace_gate.js`, a small plain script in the `<head>` (not inline: Turbo can't run an inline script from another page's nonce): a tool opened by its address in a wide window goes to `/workspace?open=…` and becomes a tile; the workspace in a narrow window goes to the tool you were on (when it is still one of yours; and a second time within moments means that page sent you back, so then to `/?one=1`). `/` goes to the workspace unless the request is a phone's or says `?one=1`.
- The workspace is marked `<body data-workspace>` (not on `<html>`: Turbo brings a new body and leaves `<html>` as the first page had it). The page has `turbo-cache-control: no-cache` (a snapshot would hold copies of the frames), `#workspace-tiles` is `data-turbo-permanent`, and the page around the tiles is morphed again now and then (`freshen`) so the menu and the launcher stay current: never while a menu or dialog is open, and **never by a Turbo visit**. A visit that fails (no network after the lid opens, a 500, new assets after a deploy) reloads or replaces the whole page, tiles included; `freshen` fetches the page itself and only morphs in an answer that is this page (`Turbo.morphBodyElements`).
- **A desktop is a binary tree** of splits with tiles as leaves. A new tile halves the one you are on (side by side when wide, stacked when tall); when those halves would be too small it halves the biggest tile with room, and when none has, it takes the next free desktop. Tiles are flat children of one element, placed with `left/top/width/height`: **a frame that moves in the DOM reloads**, so nothing ever re-parents. Rearranging animates with a transform. Nine desktops; tiles elsewhere stay loaded and hidden, and a desktop's frames are created when you first go there.
- **The menu and the launcher are one.** Cmd+K, Alt+M and the logo open the sidebar as a panel in the middle of the window (`body[data-workspace] .sidebar` in `workspace.css`), with the keyboard in the search at its top. With nothing typed it is the sidebar as it is everywhere (tools in your order, groups, reorder, add, settings; down from the field goes into the tools). What you type is found in its place: `shared/command_palette` rendered with `menu: true` in `shared/sidebar`, the same controller with `menuValue`, which asks the workspace for the menu (`command-palette:show` / `hide`) instead of opening a dialog. Pages that aren't the workspace keep the dialog, and Cmd+Shift+K in a tile opens that tile's own.
- **A tool's settings saved from the menu** (its name, its mail account) end in a redirect to the tool, which is caught like any visit to one; because a form about that tool was just sent (`turbo:submit-end`), its tiles are drawn again where they are (`refresh`: a visit to the page's own address, so a morph), the page around them too, and you stay where you were. A new tool opens as a tile. Someone's own name or picture changed in the profile shows in a tile from its next page on.
- Anything on the workspace page that visits a tool (menu, notification, the redirect after a form) is caught in `turbo:before-visit` and opened as a tile; a tool that is open is gone to instead, unless a tile of its own was asked for (Shift+Enter in the menu's search, Alt+click in a tile).
- **Keys** (`services/workspace_keys.js`) go with Alt, on a Mac with Control+Option: arrows or HJKL go to a tile, with Shift they move it, 1–9 is a desktop, F the tile alone, plus and minus resize, W closes, M the menu, R reloads; F6 goes on to the next tile. They are caught in the capture phase on the workspace page and in every tile (`tile_page_controller.js`, which hands them on with `postMessage`, along with the launcher key, the tile's address and where the keyboard is). Write them with `workspace_key("M")` ("Ctrl+Opt+M" / "Alt+M"; in words on a Mac too, the signs ⌃ ⌥ ⌘ are on few keyboards but Apple's). The modifier is **a choice per browser** (the shortcuts dialog, a `workspace_keys` cookie: Ctrl+Opt, Ctrl+Cmd or Opt+Cmd on a Mac, Alt or Ctrl+Alt elsewhere), because those keys are taken on some machines; a choice rewrites the keys a page names where they stand (`renameWorkspaceKeys`), in the workspace and every tile, without loading anything again. Control+Option is also VoiceOver's key and Alt belongs to some window managers, so **every command is in the launcher by name too** (`workspaces/_launcher_actions`, shown once you type towards one): a new command gets a row there.
- **The keyboard is at one of two levels.** *On a tile* (the tile element itself has the keyboard, `tabindex="-1"`, `workspace_controller.js#tileKeyed`): the arrows go to the tile on that side (`stepToward`), up to the bar, sideways past the last tile on to the next desktop with something on it; Enter (or Space) goes into the tool; Escape closes the tile. *In a tool* (its frame has the keyboard): the keys are the tool's, and Escape, once there is nothing left to let go of, comes back out to the tile (`tile_page_controller.js` says `escape`). `this.held` is the level; `grabFocus()` puts the keyboard back at the level it was at, `grabFocus({ into: true })` into the tool (a tool just opened, a click), `{ into: false }` on the tile (down from the bar). The workspace opens on the tile. The levels look different: both edges are in the accent colour; a tile whose tool has the keyboard has the heavier one, a tile with the keyboard on it a thin one, with what is in it stepped back and a line about Enter and Esc. The workspace's own keys work at both levels and keep the one you are at.
- For whoever can't see it: a tile, its frame and its close button are named after what is in it (`nameTile`), the tile you are on is `aria-current`, what happens to tiles is said in the bar's `role="status"` (`say`), and while the menu is in, its button is `aria-expanded` and the tiles are `inert` (`menuChanged`, which hangs on the sidebar's class because others open and close it too).
- The account and notification menus live in the sidebar, which is `visibility: hidden` while it is away; they are made visible again when open (`workspace.css`). That is also why the menu fades in by an animation and never by an opacity of its own.
- Taking a frame away takes its page along without the browser asking, so the workspace asks: it sends the page a `beforeunload` of its own and shows the confirmation dialog when that is refused (an unsent mail, a call). A tile sent away from its tool goes back to its tool once before it is dropped; a tile showing the sign-in page reloads the workspace.
- A page that is a tile is **drawn denser** (`:root[data-in-tile]` in `workspace.css`): a 14px root and a smaller Tailwind `--spacing`, plus rules per tool (one-line mail conversations, small faces in chat, tighter cards and rows, documents set smaller). It also goes without the view transition, which Turbo waits for.
- **The desktops in the bar say what goes on.** Each button shows its tools by their menu icons: the tile you'd land on lit, a dot on a tool with something new that you aren't looking at, a green one on a room with a call on; resting the pointer on a button shows a card with the tiles by name (go to one, close one). The marks come from the menu (`data-unread` on a tool's link, `data-in-call` on its item, set by `notifications_controller.js`), which the workspace watches. A tool whose tile is in sight (`inSight`: on this desktop, not hidden, window in front) is seen: its dot is taken off and the server is told (`POST /tools/:id/visit`, `Tools::VisitsController`), because a tile gets its news live and opens no page that would say so. The menu's button carries the dot for tools that aren't open anywhere. A desktop can be given a name (`renameDesk`: its name in the card, a double click on it in the bar, or "Rename this desktop" in the menu's search), which the bar shows beside its number; it is kept with the rest of the state, and a named desktop stays in the bar while it is empty.
- **The arrangement is the person's, not the browser's.** State (trees, focus, each tile's address, desktop names) is kept on the server (`WorkspaceLayout`, one per user: `state` as the browser made it, and a `revision`), so every browser opens with the same tiles. The page starts from what is kept (`data-workspace-kept-value`), a change goes to `PATCH /workspace` a moment after it was made (and once more as the page leaves), and the other browsers hear of it on the notification stream (`type: "workspace"`) and take it over (`adopt`): tiles come and go, a tile follows to the page the other browser took it to. A window nobody looks at waits until it is looked at again. A change is sent with the revision it was made from and refused (409) when that is no longer the newest; the browser then does its change again on what is kept (`withChanges`) instead of overwriting or losing either. A tile with unfinished work (an unsent mail, a call) stays where it is whatever another browser did. Tile ids are random, so two browsers never mean different tiles by one name. `localStorage` holds a copy for the narrow-window gate, with the arrangement it was made from and whether it holds a change still to send: a page that left before its change got to the server (or while it was on its way) has it done again by the next page, on top of what is kept. The server only keeps and counts; `cleaned` in the controller's script is what makes sense of a state, and writes it the same way every time so two can be compared as text. Access tokens can't touch it.
- Tests: system tests try every tool as a page of its own in a wide window, which nobody gets outside them. `sign_in_as` asks for that with a `workspace=off` cookie that only the test environment listens to (`workspace_wanted?`); `test/system/workspace_test.rb` deletes it again.

### A tile as part of the workspace's page

**A tile is a part of the workspace's own page**: a `<turbo-frame class="tile-frame">` with the tool's page in it, the same views and controllers as a page of its own (`services/tool_frame.js#pageFrame`, `workspace_controller.js#inThisPage`). One document, one line to the server, and a dialog is simply a dialog over the window. That is so for every kind of tool but a room (`IN_THIS_PAGE` in `workspace_controller.js`): **a room is still an `<iframe>`**, a document of its own as the section above describes, because a call is better off in a document that nothing else draws in. So both ways are in the code, and what the section above says about frames and keys handed on by `postMessage` is true of a room and of nothing else: there is no way to ask for another kind in a frame. Tests that try what only a frame does open a room (`launch_room` in `test/system/workspace_test.rb`).

- **The server** answers a request whose `Turbo-Frame` is `tile-…` with the page and nothing around it (`layouts/tile_frame`, `tile_frame` in `ApplicationController`). To everything else such a request is a page's, not a frame's: `tile?` is true and `turbo_frame_request?` false.
- **What a document has to itself, such a tile shares**, so a tool that moves over gives these up:
  - *The window is not its page.* Drawing the page again, going to another address of it and reading its address go through `services/tile.js` (`visitPage`, `pageAddress`), never `Turbo.visit(window.location…)`. Going on to another page of the tool from a script (a folder opened by a double click) is `openPage`. A page that shows what changes (above) draws itself that way too, so a kind that listens keeps doing so when it moves over.
  - *Its keys are not the document's.* `hotkey_controller` installs nothing in such a tile; `tile_frame_controller.js` clicks the tile's `data-hotkey` element while the keyboard is in that tile.
  - *Its ids are not alone*: two tiles of one kind are in one document. An id that is looked up (`commandfor`, a label's `for`, an anchor name) carries the tool's id.
  - *What it tells the layout* (`content_for` the shortcuts dialog and the launcher, flash) goes into `<template>`s in `layouts/tile_frame`, which `tile_frame_controller.js` puts into the workspace's own dialog and launcher while the tile is the one you are in.
  - *What is sent to its page finds it by id.* A Turbo Stream goes to the first element in the document with its target's id, so a part of a page that streams are sent to has an id of its own per record: a chat's messages are `chat_12_messages` (`Chats::Chat#part_id`), not `chat_messages`, or a second chat on the page would get the first one's messages. A view that listens for streams (`turbo:before-stream-render`) hears every tile's and tells its own by those ids.
  - *A frame inside the page whose address is the page's* (a mailbox's open conversation: `data-turbo-action="advance"` on the frame) would write it into the window's. In a tile it becomes the tile's address instead (`tile_frame_controller.js#wentOn`), so the tile comes back with that conversation and is drawn again with it. A frame that several tiles can have has an id per tool (`mail_frame_id`).
  - *Unsent work.* The workspace asks a tile before it closes it or sends it elsewhere with a `tile:leaving` event on its frame, which whoever has unsent work prevents (`compose_controller.js`); `beforeunload` is the window's. A view that asked about every visit of the window (`turbo:before-visit`) doesn't in a tile: other tiles come and go around it.
  - *A form sent from a tile* that is answered with another page of its tool (a mail sent leads to its conversation) takes that tile there (`workspace_controller.js#visiting`).
  - *Its forms are sent from the workspace's address*, so "back where you came from" (`redirect_back`) would be the workspace, which sends a tile on to the start page. The workspace says where the tile is with every request of a tile's (`X-Tile-Address`), and `ApplicationController#redirect_back_or_to` goes there: a page of the tool the request is about, else the fallback.
  - *A link with `data-turbo-action`* would put the tile's address in the window's: the tile takes the attribute off as it is clicked.
  - *The keyboard is not held for it.* In a document of its own, whatever had the keyboard and is gone (a form sent, a row drawn again) leaves it with that document. Here it would be left with the workspace's page, and the next arrow would be the bar's. So before any key is dealt with, a keyboard that is nowhere while you are in a tool goes back into that tool (`workspace_controller.js#keepKeyboardInTheTool`), and no arrow-keys controller of a tile takes a key for "the page". `data-arrow-keys-skip` on `.workspace-room` keeps the workspace's own arrows out of the tiles; it only counts for the controller it lies in, so a tile's arrows still reach its own buttons and dialogs.
- **The size smaller** is `zoom: var(--tile-zoom)` on `.tile-page` (a part of a page can't have a root of its own to measure by), with icons scaled back. Every rule that was `:root[data-in-tile] …` holds for `.tile-page …` too. What is measured by the window (`vh`) or in pixels (a board's column) is divided by `--tile-zoom` where it has to stay the size it was, or it comes out an eighth smaller. A script that turns where something is on the screen into how far to scroll divides by `drawnScale(element)` (`services/tile.js`): the one is measured as drawn, the other as laid out. Not by the zoom alone: a tile comes in a little smaller than it ends up, and a page that is there within that moment measures then. What it scrolls to goes through `onWholePixel`: seven eighths of a round number is often half a pixel, which the browser draws on the one or on the other.
- **A narrow tile**: a narrow layout written as a media query asks the window, which such a tile is not. It is written as a container query instead: `@container` on the view's `.tool-layout`, and Tailwind's container variants where the window's were (`sm:` is `@min-[40rem]:`, `md:` is `@3xl:`, `lg:` is `@5xl:`, `xl:` is `@7xl:`; see the documents' views). On a phone that is the same thing. In a tile it counts in the tile's smaller measure, so a tile is "wide" an eighth sooner than a window was, in a frame of its own and in the page alike. Mail's narrow layout is rules in a stylesheet, on the view's own root, so no container of its own can carry it: those are written under `@variant narrow` (`application.css`), which is a narrow window *or* a narrow tile (`.tile-frame` is a container called `tile`, asked in pixels as the window was). `narrow:hidden` is the same on an element. A view whose `.tool-layout` is itself laid out by width (a file's page: details beside or under the file) keeps that layout on a div inside it, since a container can't ask its own width.
- **A page that can't be laid over itself** (an editor that has to start again) is loaded from nothing with `reloadPage`. A key a view listens for on the document (the editor's Mod+S) only counts while the keyboard is in its tile.
- Tests: `test/system/workspace_test.rb` (the workspace itself, with tiles as everyone has them), `test/system/workspace_in_page_test.rb` (what every such tile does, on todos), and a file per kind for what it has of its own (`workspace_in_page_board_test.rb`, `…_chat_test.rb`, `…_docs_test.rb`, `…_calendar_test.rb`, `…_files_test.rb`, `…_mail_test.rb`).

### Installed app window

Dobase installed as an app (a browser's "Install", `display: standalone`) is marked `html[data-app-window]` by `application.js`, and `app_window.css` (unlayered, so it wins over the layers) makes it behave like an app: arrow cursor, an interface that can't be selected, no bounce.

- **No title bar.** A window can hand the strip its buttons are in to the page, and says where the buttons leave room with `env(titlebar-area-x)`, `-width` and `-height` (on a Mac the buttons are left, elsewhere right). Two windows do. A browser's installed app: the manifest asks for `display_override: ["window-controls-overlay"]`, Chromium then shows an arrow beside the window's menu, and once that is pressed (a choice per installation, nothing a page can make) the title bar is gone. And the app `dobase app install` makes, on a Mac always (`titleBarOverlay` in `cli/internal/command/shell/main.js`). **The rules for the strip ask nothing about the window they are in** (no `display-mode`, which Electron never matches): they are written in those `env()` values with nothing as the fallback, so in any other window they come to a strip no pixels high. Keep it that way: a rule that should only hold where there is a strip gets its size from `--titlebar-height` or the `env()` values.
- **In the workspace the bar is the strip**: `.workspace-bar` gets its height, stays clear of the window buttons on both sides, and is what the window is dragged by (`app-region: drag`; its buttons are `no-drag`).
- **Every other page keeps the strip free**: `--titlebar-height` (0 without the overlay, and in the workspace) pushes the sidebar's contents and `.main-content` down, and `body::before` paints the strip and makes it the place to drag. `--inset-top` is that plus a phone's status bar; use it wherever a rule needs the top of what is usable. A page in a frame (a room's tile) has no strip.
- The strip is `--color-sidebar-bg`: the browser draws its own buttons on the manifest's `theme_color`, which is that colour (`Theme#chrome_color`).
- The app from `dobase app install` reads `--titlebar-height` from the first page it loads: a server whose page keeps nothing free (one from before the rules went by `env()`) gets the window again with its title bar.
- To see it: headless Chrome can't be an installed app. `dobase app install` against a local server (a scratch `HOME`, see the CLI's notes above) shows it at once; or install the dev server as an app from a Chromium-family browser (`http://localhost` counts as secure) and press "Hide title bar" in its window. Look at the workspace, a page with the sidebar, and a narrow window.

### Arrow keys

One rule for the whole app, in `arrow_keys_controller.js`: **the arrows go to the nearest thing on that side that takes the keyboard**, by where things are on screen. It is on every page's `<main>` (`main_attributes`), on the sidebar, on the notifications, and on `<body>` for the dialogs and menus that lie outside those (`over: true`). In the workspace the arrows work at two levels (below, and under the tiling workspace). No tool has arrow-key code of its own; a view only says what its page is made of.

- **Items first.** A view marks what its page is made of with `data-arrow-keys-target="item"` (cards, rows, files, conversations, events, messages). From an item the arrows go to the next item; where the items run out on a side, into what the item has of its own there (the buttons at the end of a row), and then to **whatever else can be pressed** (a filter, the top bar, a detail view's buttons). From anything that isn't an item they go to whatever is nearest, and back among the items to the one you left them by. Nothing has to be marked for a control to be in reach.
- **A page that is read** (nothing marked: a document, an open mail) scrolls with up and down and turns with the space bar; the right arrow goes to what can be pressed on it. What lies further off than is in sight is come nearer to a step at a time, so a long text is read on the way to what is under it. A dialog or a menu is gone through the same way, within itself, and a menu that opens takes the keyboard to its first entry.
- **Fields don't hold the keyboard.** In a field the arrows are the caret's until it can go no further that way (`leavesField`: the start or end of the text, up and down in a one-line field, anywhere in an empty one); then they go on. Lists to choose from and dates are passed over (Space opens a list). Escape lets go of a field on the page (`keyboard_shortcuts_controller.js`).
- **Enter** opens an item that isn't a link or button itself; the **left arrow** clicks the `back` target (the back arrow of `tool_topbar` and `back_link`) when there is nothing to its left; with **Shift** an item that can be dragged moves (`sortable_controller.js#moveWithKeys`); **Home and End** go to the top and the bottom of the column or list, **Page Up and Page Down** about a screen.
- **Past the last thing on a side** it dispatches `arrow-keys:edge` (`detail.side`, `detail.repeat`). A view with a use for it prevents the default (the calendar: another week; mail in a narrow window: open the conversation, or back to the list). In a tile nothing follows from it: the arrows stay in the tool. When the keyboard gets somewhere it says `arrow-keys:went` on that element (mail opens the conversation beside the list; chat puts the caret in its message box).
- **Where you were on a page is kept** while the tab is open (`sessionStorage`, by the item's id or address): back in a list, the first arrow lands on what you left it by. A list that grows at its end (`data-arrow-keys-from="end"`, chat) starts at its last item instead.
- Keys are left alone under a viewer that lies over the page (`aria-modal` that isn't a `<dialog>`: the gallery) and to whoever prevented the default. What is only there for a screen reader, or can't be pressed by a pointer either, is passed over; `data-arrow-keys-skip` keeps a part of a page out.
- Per tool, beside the arrows: the space bar ticks a todo and picks a file beside what is picked; `c` on a board adds a card to the column you are in; in mail the space bar turns the page of the message.
- **Escape lets go of one thing at a time**: a dialog or menu closes, a field is left, a view lets go of what is picked (and only takes the key when there is something to let go of), the keyboard leaves the item it is on. In a tile, with nothing left to let go of, it leaves the tool: the keyboard is on the tile itself then (the left arrow is the way up a level inside a tool).

`test/system/arrow_keys_reach_test.rb` walks every tool's pages and dialogs with the arrow keys and fails on anything that can be pressed and was never reached. When a new view fails it, mark its rows as items; a control that is out of reach is usually hidden behind something or needs nothing at all.

### Sounds

`services/sound.js` makes the app's sounds: a dozen short, low, dry taps and knocks (a message sent, one arriving, a notification, new mail, mail sent, a todo ticked off, something dropped, archived, trashed, a call joined or left, an error). Nothing is loaded: each is one or two Web Audio voices (`knock`, `tap`, `click`, `air`, `note`), closer to a key being pressed than to a chime, every one over within a quarter of a second.

- **In a view**: `data-sound="send"` on a form plays when the form went through; on anything else, when it is clicked (a hotkey's click counts). **From a controller**: `play("receive", { once: "message-12" })`. `once` names what happened: with the app open in several tabs only one plays it (Web Locks).
- Arriving things: a message in the chat you are looking at is `receive` (`chat_controller.js`); a notification is `notify` unless it is about the tool you are looking at; more unread mail than before is `mail` (`notifications_controller.js`). Mail is `sent` when the mail server took it, not when Send is pressed (`mail_sending_controller.js`).
- A browser lets a page make sound only once it has been touched, so a sound before the first click or key is lost. The output is given back after a few idle seconds.
- On by default, switched off per browser (`localStorage`) under Profile, Notifications, where each sound can be tried. A new sound gets a row there (`profiles/edit`).
- Tests can't hear: the service dispatches `sound:played` for every sound it starts (`test/system/sounds_test.rb`).

### Checking a change to the frontend

The app has no build step and needs no Node. `package.json` only holds what checks it: TypeScript (as a checker of plain JavaScript) and nothing else.

- **Logic that needs no page lives in a service and is tested without a browser.** `services/workspace_layout.js` is the workspace's arrangement (the tree of splits, where a new tile goes, what is kept, a change here done again on a change there); `workspace_controller.js` draws it. Tests are `test/javascript/*.test.mjs`, run by `npm test` with Node's own test runner. `test/javascript/support/importmap.mjs` gives Node the names the browser's import map has, so a test imports `"services/tool_frame"` as the app does. When a controller grows logic of that kind (dates, geometry, merging state), put it in a service and test it there.
- **Types are JSDoc comments, checked by `npm run check`** (`tsc`, strict). Only the files in `tsconfig.json`'s `include` are checked, with whatever they import: a script goes on the list once its functions say what they take and give. The Stimulus controllers are not on it: their targets and values exist at runtime only, and checking them gave a thousand errors that were none.
- **`bin/screenshots` lays the app before a change beside the app after it.** `take <name>` draws every scene of `test/screenshots/scenes.rb` into `tmp/shots/<name>`; `compare <a> <b>` says which scenes differ by how many pixels, writes before, after and the difference side by side into `tmp/shots/<a>-<b>`, and ends with status 1 when anything differs. The scenes are the demo's example workspace (`Demo::Workspace`) on a clock that stands still, in the workspace (1400 by 900), on a phone (390 by 844) and signed out, light, dark and themed. Two runs of the same code are the same to the pixel (every scene has a browser of its own, and a room's page is held back until the tiles beside it are drawn: a browser keeps the first spacing it gave the system's typeface at a size, and a tile's letters and a room's come to one size by two ways), so use it for any change that should not show (moving CSS, another way to draw the same page): take `before` first, and `compare` must say all scenes are the same. For a change that should show, the pictures in `tmp/shots/<a>-<b>` are what to look at and to show. A new kind of page gets a scene. CI takes the pictures of every pull request (the `screenshots` job keeps them as an artifact).
- **Every screen has its half of the API** (`test/integration/api_coverage_test.rb`): a page that lists or shows something has a JSON view a token may ask for, and a form posts to an action a token may call. The test lists the screens that go without and why (nobody signed in, an account's own settings, the browser's own window); a new screen that isn't in the API fails it.

### Component System

**All UI must use components** — no freeform HTML. Components use Rails `tag.*` helpers with hash options for HTML attributes (never manual string interpolation):

```ruby
# Build options hash, compact nils, splat into tag helper
html_options = { class: classes, title: title, data: data_attrs.presence, disabled: disabled || nil }.compact
tag.button(**html_options) { content }
link_to content, href, **html_options
```

```erb
<%= render "components/button", text: "Save" %>                             # variants: :primary, :secondary, :ghost, :danger — sizes: :sm, :md
<%= render "components/icon_button", icon: "settings", title: "Settings" %> # variants: :ghost (default), :danger, :accent — sizes: :sm, :md
<%= render "components/badge", text: 5, variant: :warning %>                # variants: :default, :muted, :success, :warning, :error
<%= render "components/form_field", label: "Email", name: "email", type: :email, required: true %>  # types: :text, :email, :password, :textarea, :select, :number, :date
<%= render "components/tabs", tabs: [{label: "Inbox", href: path, active: true, icon: "inbox", badge: 3}] %>
<%= render "components/search", url: search_path, placeholder: "Search..." %>
<%= render "components/tool_topbar", title: @tool.name do %>...actions...<% end %>
<%= render "components/empty_state", title: "No messages", icon: "inbox" %>
<%= render "components/rich_text_input", name: "body", placeholder: "Write..." %>
<%= render "shared/icon", name: "check", size: 16 %>
<%= render "shared/avatar", user: @user, size: :sm %>
<%= render "shared/modal", id: "my-modal", title: "Title" do %>...content...<% end %>
<%= render "shared/error_flash", object: @user %>
```

## Principles

- Boring, readable Rails code
- No premature abstraction
- DRY: extract shared UI into reusable components
- Authorize access to every tool instance explicitly

## Key Conventions

- `frozen_string_literal: true` in all Ruby files
- Icons: Lucide (rendered via `shared/icon` partial)
- Sizes, dates and times: use `FormattingHelper` (`human_file_size`, `format_time` → "6:05 PM", `format_date` → "Sep 16" / "Sep 16, 2025", `format_datetime`), never ad-hoc `strftime` or `number_to_human_size`. Times show in the viewer's `Time.zone`.
- Fixture dates are relative to today (the calendar's meeting is tomorrow), so a test that needs an event in view opens the week of that event, not "this week": on a Sunday tomorrow is next week.
- Testing: Minitest with fixtures; namespaced models need `set_fixture_class` in test_helper. Fixtures bypass model callbacks, so `collaborators.yml` must have explicit owner records for every tool fixture (the `add_creator_as_owner` callback doesn't run for fixtures).
- Ordering: position column + dedicated `PositionsController`
- Encryption: mail/calendar passwords encrypted with `secret_key_base`
- Importmap: all JS vendored locally (`vendor/javascript/`), no CDN dependencies. Update with `bin/importmap outdated` and `bin/importmap update`. Exception: ALTCHA lives in `public/altcha.min.js` (can't use importmap due to embedded web worker)
- Releases: CalVer (`YYYY.MM.DD`). Create with `gh release create YYYY.MM.DD`
- Tool creation callbacks: Board auto-creates 3 default columns; Chat auto-creates chat record; Tool adds creator as owner collaborator
- Board deep-linking: `?card=ID` URL param auto-opens card detail modal on board page load. Notification URLs use this pattern (`tool_board_path(tool, card: card.id)`)
- Tabs with URL persistence: `tabs_controller` reads `?tab=` query param to restore active tab across redirects. Always include `tab:` param in redirects that should preserve tab state.
- A form in a frame that is answered with a page without that frame (an event saved from its dialog, redirected to the calendar) goes to that page: `application.js` listens for `turbo:frame-missing`. Turbo alone writes "Content missing" into the frame.
- Turbo frames in modals: Forms inside `<dialog>` should use turbo frames to update content in-place (e.g., share link appearing after creation). Use `turbo_frame: "_top"` on actions that should close the modal via full-page navigation (e.g., delete/destroy).
- `data-turbo-permanent` elements must live **outside `<main>`** to survive Turbo navigations — Turbo replaces `<main>` content on visit. Place them as siblings of `<main>` in the layout.
- **Turbo morph** (`turbo-refresh-method: morph` in layout) can break pages with complex dynamic content (rhino-editor, custom elements). If a page doesn't render correctly after redirect, the morph is likely dropping content. Fix by ensuring elements have stable IDs.
- Flash messages: The `shared/flash` partial supports `position: :toast` (default, fixed bottom-right) and `position: :inline` (within forms). Auth pages (login, signup, password reset) use inline flash. The toast only renders for logged-in users.
- `track_last_visited_path` excludes `/sync` paths to avoid polluting the redirect-after-login target.
- Prefer CSS-driven state over JS DOM manipulation when possible. For example, use `body:has([data-some-value="active"])` to conditionally show/hide elements elsewhere in the page, rather than querying the DOM from a Stimulus controller. CSS `:has()` selectors are powerful for cross-component state.
- Tool layout CSS: Use `auto` for topbar grid rows (not fixed px values) so they size naturally from the `tool-topbar` component. Avoid duplicate borders between adjacent elements (topbar `border-b` + content `border-t`).
- Icons: New icons must be added to `app/views/shared/_icon.html.erb` hash — SVG paths from Lucide
