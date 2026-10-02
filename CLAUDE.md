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
```

## Deployment

```bash
kamal deploy -d dobase     # Deploy to production (requires -d dobase destination flag)
kamal console -d dobase    # Rails console on production
kamal logs -d dobase       # Tail production logs
```

The `config/deploy.yml` contains open-source placeholder values. Real production config lives in `config/deploy.dobase.yml` (the Kamal destination file). Always use `-d dobase` when deploying.

Docker images are published to `ghcr.io/smgdkngt/dobase` via `.github/workflows/publish-image.yml` on push to main and CalVer tags (e.g., `2026.04.07`). Compatible with [ONCE](https://once.com) by 37signals.

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

`cli/` holds the `dobase` command-line client (Go, standard library plus `golang.org/x/term` and tcell; one binary per platform, cross-compiled and attached to every GitHub release by `.github/workflows/cli-release.yml`; `cli/install.sh` downloads it) and its Claude Code skill (`cli/SKILL.md`). Commands are declared per noun in `cli/internal/commands/*.go` with `New("noun verb", summary, []string{ARGS}, []Flag{flags}, function)`; `dobase help` is generated from those. API responses are `api.Value` (ordered JSON: `.Get("a", "b").S()`, missing reads as empty), so `--json` prints what the server sent. `dobase` without arguments in a terminal opens a full-screen app (`cli/internal/tui/`, tcell): a screen per tool type, network work queued as jobs so a spinner shows first, live screens refreshed every 10s on a background goroutine (stale results dropped), undo on `u`, tests drive it by key presses against a fake API on a simulated screen. `go test ./...` in `cli/` checks every command and that the examples in `cli/SKILL.md` and the READMEs exist; the CI `cli` job runs it with `go vet` and `gofmt`. When adding an endpoint the CLI should use, add the command, update `cli/SKILL.md` if it changes how an agent should behave, and smoke-test against `bin/dev` with `DOBASE_URL`/`DOBASE_TOKEN` (`go run . ...`).

### Real-time (ActionCable)

- **ChatChannel** — messaging, typing indicators, presence
- **DocumentSyncChannel** — shared Yjs editing of a document: stores and relays updates (`Docs::Update`), relays cursors (awareness), and marks the document "open" (`locked_by`) for the documents list and the API. A write from outside the editor throws that copy away (`Docs::Document#reset_shared_copy!` bumps `shared_copy_generation`): changes to an older copy are refused and open editors load the document again. The vendored rhino-editor bundle carries the Collaboration extensions; see `vendor/javascript/README.md`
- **DocumentChannel** — read-only viewers of a document: saved content and whether someone has it open
- **PresenceChannel** — who is in a tool and what they have open (`presence:context` events, `data-presence-item`/`data-presence-target` in views), plus comment typing. Nothing stored: pages announce every 30s and forget anyone quiet for 90s. **WorkspacePresenceChannel** listens to every shared tool for the sidebar faces
- **NotificationChannel** — per-user stream (`notifications:#{user.id}`) for real-time notification delivery
- Action Cable only passes the payload to an action with exactly one required argument (`def announce(data)`), and `transmit` needs a braced hash
- Connection authenticates via signed session cookie

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
- A theme reaches everything: the label hues (`--color-label-*`: card labels, tool type icons), the logo (`shared/logo`, drawn inline in `--color-logo`), native controls (`accent-color`), selection and scrollbars. Pages with nobody signed in (sign-in, shared links, the manifest) use the theme the browser last had, kept in a signed `theme` cookie (`remember_theme`, `remembered_theme`); the offline page reads a few colours from `localStorage`. Cmd+K offers every theme once you type towards one.
- The typeface is a setting of its own (`users.typeface`, `"mono"` or nil, `data-typeface` on `<html>`): mono points `--font-family-sans` at the monospace stack, which ends in the generic `monospace` and names no font a Linux desktop has, so on Omarchy it is the desktop's font (fontconfig). `--font-family-ui` is always the app's own.
- Mail the app sends wears the reader's theme and typeface too: `MailerHelper` looks the recipient up by address (`mail_reader`) and gives every mailer view its colours through `mail_color(:text)` and `mail_font`, never a hex in a view. Without a theme the mail keeps the app's own look, with the dark set in the layout's `<style>`. The logo in a themed mail is `/logos/<fill>-<ink>.png` (`LogosController`: the shipped PNG recoloured, open to anyone, since libvips' SVG loader is blocked).
- Styling for a theme must come from tokens. What sits on an accent or danger fill is `text-text-inverse` (white or the theme's darkest colour), never `text-white`. Dark-only rules can't use `prefers-color-scheme` alone: add `:root[data-theme-mode="dark"]` (see `.email-frame`, `rhino-editor`).

### Avatars (Active Storage)

`User` model: `has_one_attached :avatar` with content type (PNG/JPEG/GIF/WebP) and size (5MB) validation. Displayed via `shared/avatar` partial with `variant(resize_to_fill: [200, 200])`. Requires `libvips` system library. Without a picture it is the initials in one of the theme's label colours over a shape in a second one, the same for the same person everywhere (`User#avatar_look`, `.avatar[data-avatar-hue]` in `components.css`; faces drawn in the browser get it through `services/avatar.js`).

### Email Tool (IMAP/SMTP)

All mail actions sync to the IMAP server: trash, archive, read/unread, star, move, delete. The `ImapSyncService` handles IMAP operations; controllers call `ImapSyncJob.perform_later` for async sync. The `archive_folder` setting on `Mails::Account` determines whether archiving moves to an IMAP folder or just marks as read.

Mail drafts save locally and sync to the IMAP Drafts folder via `SyncDraftJob`. Files are attached to a saved draft through `Mails::DraftAttachmentsController` (the API and CLI's `--attach`). The server's trash folder is always `Trash` here, whatever the server calls it, and is not a folder to move to. A draft is trashed, moved and restored by itself, never with the conversation it answers; in the trash it stays `draft: true` (out of the `drafts` scope, shown as mail), and restoring puts it back in Drafts. The compose form uses `formaction` on the Save Draft button to submit to the drafts controller.

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

- **A tile is a tool's own page in an `<iframe name="workspace-tile">`.** The layout draws it without the sidebar, the notifications and the bottom bar when `tile?` (`ApplicationController`) is true: `Sec-Fetch-Dest: iframe` on the frame's first load, and the `X-Tile` header Turbo sends from inside the frame (`application.js`, which also marks `<html data-in-tile>` and asks again when the server didn't hear: plain HTTP, an old service worker). Its window is narrow, so a tool gets its **narrow-screen layout** by the media queries a phone uses, minus the bottom bar. No tool knows about tiles.
- A tile request touches `last_seen_at` but never `last_visited_path`, never stores a return-to address, and never gets the workspace itself. The service worker leaves frame navigations alone (fetched from there they lose `Sec-Fetch-Dest`); system tests switch the service worker off, so that path only shows in a real browser. CSP has `frame-ancestors 'self'`.
- **Where a window goes** is decided before the page is drawn by `workspace_gate.js`, a small plain script in the `<head>` (not inline: Turbo can't run an inline script from another page's nonce): a tool opened by its address in a wide window goes to `/workspace?open=…` and becomes a tile; the workspace in a narrow window goes to the tool you were on (when it is still one of yours; and a second time within moments means that page sent you back, so then to `/?one=1`). `/` goes to the workspace unless the request is a phone's or says `?one=1`.
- The workspace is marked `<body data-workspace>` (not on `<html>`: Turbo brings a new body and leaves `<html>` as the first page had it). The page has `turbo-cache-control: no-cache` (a snapshot would hold copies of the frames), `#workspace-tiles` is `data-turbo-permanent`, and the page around the tiles is morphed again now and then (`freshen`) so the menu and the launcher stay current: never while a menu or dialog is open, and **never by a Turbo visit**. A visit that fails (no network after the lid opens, a 500, new assets after a deploy) reloads or replaces the whole page, tiles included; `freshen` fetches the page itself and only morphs in an answer that is this page (`Turbo.morphBodyElements`).
- **A desktop is a binary tree** of splits with tiles as leaves. A new tile halves the one you are on (side by side when wide, stacked when tall); when those halves would be too small it halves the biggest tile with room, and when none has, it takes the next free desktop. Tiles are flat children of one element, placed with `left/top/width/height`: **a frame that moves in the DOM reloads**, so nothing ever re-parents. Rearranging animates with a transform. Nine desktops; tiles elsewhere stay loaded and hidden, and a desktop's frames are created when you first go there.
- **The menu and the launcher are one.** Cmd+K, Alt+M and the logo open the sidebar as a panel in the middle of the window (`body[data-workspace] .sidebar` in `workspace.css`), with the keyboard in the search at its top. With nothing typed it is the sidebar as it is everywhere (tools in your order, groups, reorder, add, settings; down from the field goes into the tools). What you type is found in its place: `shared/command_palette` rendered with `menu: true` in `shared/sidebar`, the same controller with `menuValue`, which asks the workspace for the menu (`command-palette:show` / `hide`) instead of opening a dialog. Pages that aren't the workspace keep the dialog, and Cmd+Shift+K in a tile opens that tile's own.
- **A tool's settings saved from the menu** (its name, its mail account) end in a redirect to the tool, which is caught like any visit to one; because a form about that tool was just sent (`turbo:submit-end`), its tiles are drawn again where they are (`refresh`: a visit to the page's own address, so a morph), the page around them too, and you stay where you were. A new tool opens as a tile. Someone's own name or picture changed in the profile shows in a tile from its next page on.
- Anything on the workspace page that visits a tool (menu, notification, the redirect after a form) is caught in `turbo:before-visit` and opened as a tile; a tool that is open is gone to instead, unless a tile of its own was asked for (Shift+Enter in the menu's search, Alt+click in a tile).
- **Keys** (`services/workspace_keys.js`) go with Alt, on a Mac with Control+Option: arrows or HJKL go to a tile, with Shift they move it, 1–9 is a desktop, F the tile alone, plus and minus resize, W closes, M the menu, R reloads; F6 goes on to the next tile. They are caught in the capture phase on the workspace page and in every tile (`tile_page_controller.js`, which hands them on with `postMessage`, along with the launcher key, the tile's address and where the keyboard is). Write them with `workspace_key("M")` ("Ctrl+Opt+M" / "Alt+M"; in words on a Mac too, the signs ⌃ ⌥ ⌘ are on few keyboards but Apple's). The modifier is **a choice per browser** (the shortcuts dialog, a `workspace_keys` cookie: Ctrl+Opt, Ctrl+Cmd or Opt+Cmd on a Mac, Alt or Ctrl+Alt elsewhere), because those keys are taken on some machines; a choice rewrites the keys a page names where they stand (`renameWorkspaceKeys`), in the workspace and every tile, without loading anything again. Control+Option is also VoiceOver's key and Alt belongs to some window managers, so **every command is in the launcher by name too** (`workspaces/_launcher_actions`, shown once you type towards one): a new command gets a row there.
- For whoever can't see it: a tile, its frame and its close button are named after what is in it (`nameTile`), the tile you are on is `aria-current`, what happens to tiles is said in the bar's `role="status"` (`say`), and while the menu is in, its button is `aria-expanded` and the tiles are `inert` (`menuChanged`, which hangs on the sidebar's class because others open and close it too).
- The account and notification menus live in the sidebar, which is `visibility: hidden` while it is away; they are made visible again when open (`workspace.css`). That is also why the menu fades in by an animation and never by an opacity of its own.
- Taking a frame away takes its page along without the browser asking, so the workspace asks: it sends the page a `beforeunload` of its own and shows the confirmation dialog when that is refused (an unsent mail, a call). A tile sent away from its tool goes back to its tool once before it is dropped; a tile showing the sign-in page reloads the workspace.
- A page that is a tile is **drawn denser** (`:root[data-in-tile]` in `workspace.css`): a 14px root and a smaller Tailwind `--spacing`, plus rules per tool (one-line mail conversations, small faces in chat, tighter cards and rows, documents set smaller). It also goes without the view transition, which Turbo waits for.
- **The desktops in the bar say what goes on.** Each button shows its tools by their menu icons: the tile you'd land on lit, a dot on a tool with something new that you aren't looking at, a green one on a room with a call on; resting the pointer on a button shows a card with the tiles by name (go to one, close one). The marks come from the menu (`data-unread` on a tool's link, `data-in-call` on its item, set by `notifications_controller.js`), which the workspace watches. A tool whose tile is in sight (`inSight`: on this desktop, not hidden, window in front) is seen: its dot is taken off and the server is told (`POST /tools/:id/visit`, `Tools::VisitsController`), because a tile gets its news live and opens no page that would say so. The menu's button carries the dot for tools that aren't open anywhere.
- **A tile's big dialogs float over all the tiles**, the way a window manager floats a dialog over tiled windows (`services/float.js`). Nothing in a frame can lie outside it, so a card's, a todo's and an event's details aren't opened in the tile: the tile asks the workspace (`floats(url)`), which loads **the tool's own page once more** in a frame as large as the window (`name="workspace-float"`, `#workspace-float`), at the address that opens the dialog by itself (`?card=`, `?item=`, `?event=`). That page shows nothing but its dialog (`:root[data-floating]` in `workspace.css`: the rest is invisible and see-through), so every button in the dialog works as anywhere and the dialog has the whole window's width. When the dialog closes, or the page goes somewhere without one, the frame is taken away and the tile it came from is drawn again (`tile_page_controller.js#float`, `workspace_controller.js#unfloat`). Small dialogs (a new folder, a confirmation) stay in their tile. A new dialog that should float needs an address that opens it and one `floats(...)` line where it opens.
- State (trees, focus, each tile's address) is in `localStorage` per person.
- Tests: system tests try every tool as a page of its own in a wide window, which nobody gets outside them. `sign_in_as` asks for that with a `workspace=off` cookie that only the test environment listens to (`workspace_wanted?`); `test/system/workspace_test.rb` deletes it again.

### Arrow keys

One rule for the whole app, in `arrow_keys_controller.js`: **the arrows go to the nearest thing on that side that takes the keyboard**, by where things are on screen. It is on every page's `<main>` (`main_attributes`), on the sidebar, on the notifications, and on `<body>` for the dialogs and menus that lie outside those (`over: true`). In the workspace, up from the top of a tile is the bar, and down from the bar is the tile again. No tool has arrow-key code of its own; a view only says what its page is made of.

- **Items first.** A view marks what its page is made of with `data-arrow-keys-target="item"` (cards, rows, files, conversations, events, messages). From an item the arrows go to the next item; where the items run out on a side, into what the item has of its own there (the buttons at the end of a row), and then to **whatever else can be pressed** (a filter, the top bar, a detail view's buttons). From anything that isn't an item they go to whatever is nearest, and back among the items to the one you left them by. Nothing has to be marked for a control to be in reach.
- **A page that is read** (nothing marked: a document, an open mail) scrolls with up and down and turns with the space bar; the right arrow goes to what can be pressed on it. What lies further off than is in sight is come nearer to a step at a time, so a long text is read on the way to what is under it. A dialog or a menu is gone through the same way, within itself, and a menu that opens takes the keyboard to its first entry.
- **Fields don't hold the keyboard.** In a field the arrows are the caret's until it can go no further that way (`leavesField`: the start or end of the text, up and down in a one-line field, anywhere in an empty one); then they go on. Lists to choose from and dates are passed over (Space opens a list). Escape lets go of a field on the page (`keyboard_shortcuts_controller.js`).
- **Enter** opens an item that isn't a link or button itself; the **left arrow** clicks the `back` target (the back arrow of `tool_topbar` and `back_link`) when there is nothing to its left; with **Shift** an item that can be dragged moves (`sortable_controller.js#moveWithKeys`); **Home and End** go to the top and the bottom of the column or list, **Page Up and Page Down** about a screen.
- **Past the last thing on a side** it dispatches `arrow-keys:edge` (`detail.side`, `detail.repeat`). A view with a use for it prevents the default (the calendar: another week; mail in a narrow window: open the conversation, or back to the list). In the workspace `tile_page_controller.js` hears what nobody took and the tile on that side takes over, so the arrows go from tool to tool; not while a key is held down. When the keyboard gets somewhere it says `arrow-keys:went` on that element (mail opens the conversation beside the list; chat puts the caret in its message box).
- **Where you were on a page is kept** while the tab is open (`sessionStorage`, by the item's id or address): back in a list, the first arrow lands on what you left it by. A list that grows at its end (`data-arrow-keys-from="end"`, chat) starts at its last item instead.
- Keys are left alone under a viewer that lies over the page (`aria-modal` that isn't a `<dialog>`: the gallery) and to whoever prevented the default. What is only there for a screen reader, or can't be pressed by a pointer either, is passed over; `data-arrow-keys-skip` keeps a part of a page out.
- Per tool, beside the arrows: the space bar ticks a todo and picks a file beside what is picked; `c` on a board adds a card to the column you are in; in mail the space bar turns the page of the message.
- **Escape lets go of one thing at a time**: a dialog or menu closes, a field is left, a view lets go of what is picked (and only takes the key when there is something to let go of), the keyboard leaves the item it is on. In a tile with nothing left to let go of, it closes the tile.

`test/system/arrow_keys_reach_test.rb` walks every tool's pages and dialogs with the arrow keys and fails on anything that can be pressed and was never reached. When a new view fails it, mark its rows as items; a control that is out of reach is usually hidden behind something or needs nothing at all.

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
- Testing: Minitest with fixtures; namespaced models need `set_fixture_class` in test_helper. Fixtures bypass model callbacks, so `collaborators.yml` must have explicit owner records for every tool fixture (the `add_creator_as_owner` callback doesn't run for fixtures).
- Ordering: position column + dedicated `PositionsController`
- Encryption: mail/calendar passwords encrypted with `secret_key_base`
- Importmap: all JS vendored locally (`vendor/javascript/`), no CDN dependencies. Update with `bin/importmap outdated` and `bin/importmap update`. Exception: ALTCHA lives in `public/altcha.min.js` (can't use importmap due to embedded web worker)
- Releases: CalVer (`YYYY.MM.DD`). Create with `gh release create YYYY.MM.DD`
- Tool creation callbacks: Board auto-creates 3 default columns; Chat auto-creates chat record; Tool adds creator as owner collaborator
- Board deep-linking: `?card=ID` URL param auto-opens card detail modal on board page load. Notification URLs use this pattern (`tool_board_path(tool, card: card.id)`)
- Tabs with URL persistence: `tabs_controller` reads `?tab=` query param to restore active tab across redirects. Always include `tab:` param in redirects that should preserve tab state.
- Turbo frames in modals: Forms inside `<dialog>` should use turbo frames to update content in-place (e.g., share link appearing after creation). Use `turbo_frame: "_top"` on actions that should close the modal via full-page navigation (e.g., delete/destroy).
- `data-turbo-permanent` elements must live **outside `<main>`** to survive Turbo navigations — Turbo replaces `<main>` content on visit. Place them as siblings of `<main>` in the layout.
- **Turbo morph** (`turbo-refresh-method: morph` in layout) can break pages with complex dynamic content (rhino-editor, custom elements). If a page doesn't render correctly after redirect, the morph is likely dropping content. Fix by ensuring elements have stable IDs.
- Flash messages: The `shared/flash` partial supports `position: :toast` (default, fixed bottom-right) and `position: :inline` (within forms). Auth pages (login, signup, password reset) use inline flash. The toast only renders for logged-in users.
- `track_last_visited_path` excludes `/sync` paths to avoid polluting the redirect-after-login target.
- Prefer CSS-driven state over JS DOM manipulation when possible. For example, use `body:has([data-some-value="active"])` to conditionally show/hide elements elsewhere in the page, rather than querying the DOM from a Stimulus controller. CSS `:has()` selectors are powerful for cross-component state.
- Tool layout CSS: Use `auto` for topbar grid rows (not fixed px values) so they size naturally from the `tool-topbar` component. Avoid duplicate borders between adjacent elements (topbar `border-b` + content `border-t`).
- Icons: New icons must be added to `app/views/shared/_icon.html.erb` hash — SVG paths from Lucide
