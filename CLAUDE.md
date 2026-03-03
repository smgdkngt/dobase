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

Config lives in `config/initializers/app_config.rb`. View helpers: `app_name`, `app_logo_path`.

## Development Commands

```bash
bin/dev                    # Start dev server (Rails + Tailwind watcher via foreman)
bin/setup                  # Install deps + prepare DB (--reset to drop/recreate)
bin/rails test             # Run unit/integration tests (Minitest)
bin/rails test:system      # Run system tests (Capybara + Selenium)
bin/rails test test/models/tool_test.rb           # Run single test file
bin/rails test test/models/tool_test.rb:42        # Run single test at line
bin/rubocop                # Lint Ruby (rubocop-rails-omakase)
bin/brakeman --quiet       # Security static analysis
bin/ci                     # Full CI pipeline (setup, lint, audit, tests, seeds)
```

## Deployment

```bash
kamal deploy -d dobase     # Deploy to production (requires -d dobase destination flag)
```

The `config/deploy.yml` contains open-source placeholder values. Real production config lives in `config/deploy.dobase.yml` (the Kamal destination file). Always use `-d dobase` when deploying.

**Tailwind CSS** must be rebuilt after stylesheet changes:
```bash
bundle exec tailwindcss -i ./app/assets/tailwind/application.css -o ./app/assets/builds/application.css
```
The `bin/dev` watcher handles this automatically in development.

## Architecture

### Tool System

Every feature is a **Tool** instance linked to a **ToolType** (slug: `mail`, `boards`, `files`, `chat`, `docs`, `calendar`, `room`, `todos`). `ToolsController#show` redirects to the tool-specific controller based on slug.

**Permissions are binary.** Checked via `ToolAuthorization` concern (`can_access?` / `can_manage?`). Access is tracked in the `collaborators` table with a `role` column:
- **Owner** (`role: "owner"`) — full control, can invite/remove collaborators, promote to owner, rename, delete. Tools can have multiple owners.
- **Collaborator** (`role: "collaborator"`) — full functional access within the tool, cannot delete or re-share

The tool creator is automatically added as an owner collaborator (`after_create :add_creator_as_owner`). Check ownership via `tool.owned_by?(user)` and access via `tool.accessible_by?(user)` — both query the collaborators table. Permissions are explicit and instance-based — never inferred.

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

### Real-time (ActionCable)

- **ChatChannel** — messaging, typing indicators, presence
- **DocumentChannel** — collaborative editing broadcasts
- **NotificationChannel** — per-user stream (`notifications:#{user.id}`) for real-time notification delivery
- Connection authenticates via signed session cookie

### Rich Text (ActionText + Lexxy)

Lexxy gem replaces Trix. Two editor modes:
- **Full** (Docs): `.document-editor` / `.document-view` classes, large text, full toolbar
- **Compact** (Chat/Comments): `.rich-text-input` wrapper, pruned toolbar (bold/italic/link/code), inherits font size from context

Models use `has_rich_text :body`. The `rich_text_input` component wraps `rich_text_area_tag` with a Stimulus controller for enter-to-submit and toolbar pruning.

### Background Jobs

Solid Queue (database-backed). Key jobs: `ImapSyncJob`, `SyncEmailsJob`, `SyncCalendarsJob`.

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

**Notifiers**: `ToolInvitationNotifier`, `ChatMessageNotifier`, `CardCommentNotifier`, `CardAssignmentNotifier`. All param access must be nil-safe (`&.name`, `&.title`) since referenced records can be deleted.

**UI**: Bell icon in sidebar with unread badge. Popover loads notification list via Turbo Frame. Stimulus `notifications_controller` subscribes to ActionCable for real-time badge updates.

### Invitations & Collaboration

Collaborators are always added via invitation (never direct-add). Flow:
1. Owner sends invitation → `CollaboratorMailer#invitation` email + `ToolInvitationNotifier` (if user exists)
2. Recipient visits acceptance link → `InvitationAcceptancesController#show` (confirmation page)
3. Accept (POST) creates collaborator record, Decline (DELETE) marks invitation as declined
4. Unauthenticated users are redirected to login/signup with return-to session tokens

`Invitation` model: auto-generates token, 7-day expiry, statuses: `pending`/`accepted`/`declined`. Declined invitations show in collaborators panel with a "Reinvite" option.

### Avatars (Active Storage)

`User` model: `has_one_attached :avatar` with content type (PNG/JPEG/GIF/WebP) and size (5MB) validation. Displayed via `shared/avatar` partial with `variant(resize_to_fill: [200, 200])`. Requires `libvips` system library.

### Email Delivery

SMTP configured in `config/environments/production.rb` via Rails credentials (`smtp.user_name`, `smtp.password`, `smtp.address`, `smtp.port`). Shared mailer layout in `app/views/layouts/mailer.html.erb`. Default from address uses `APP_FROM_EMAIL` env var.

### Authentication

Session-based with `Current` (ActiveSupport::CurrentAttributes). `Current.user` available everywhere. Sessions stored in DB with IP/user-agent tracking.

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

**Cascade layer note:** Tailwind v4 puts component styles in `@layer components`. Unlayered styles (Tailwind utility classes in ERB, Lexxy CSS) always beat `@layer components` rules regardless of specificity. This means:
- **Never use inline Tailwind utility classes on elements whose styles need to be overridden by `@layer components` CSS.** Instead, use semantic CSS classes (e.g., `.room-controls` instead of `flex items-center gap-2 px-4 py-3`) so that both the base style and mode-specific overrides live in the same layer and cascade normally.
- To override Lexxy specifically, use `!important` via Tailwind's `!` suffix (e.g., `border-none!`).

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
- Testing: Minitest with fixtures; namespaced models need `set_fixture_class` in test_helper. Fixtures bypass model callbacks, so `collaborators.yml` must have explicit owner records for every tool fixture (the `add_creator_as_owner` callback doesn't run for fixtures).
- Ordering: position column + dedicated `PositionsController`
- Encryption: mail/calendar passwords encrypted with Rails credentials
- Tool creation callbacks: Board auto-creates 3 default columns; Chat auto-creates chat record; Tool adds creator as owner collaborator
- Board deep-linking: `?card=ID` URL param auto-opens card detail modal on board page load. Notification URLs use this pattern (`tool_board_path(tool, card: card.id)`)
- Tabs with URL persistence: `tabs_controller` reads `?tab=` query param to restore active tab across redirects. Always include `tab:` param in redirects that should preserve tab state.
- Turbo frames in modals: Forms inside `<dialog>` should use turbo frames to update content in-place (e.g., share link appearing after creation). Use `turbo_frame: "_top"` on actions that should close the modal via full-page navigation (e.g., delete/destroy).
- `data-turbo-permanent` elements must live **outside `<main>`** to survive Turbo navigations — Turbo replaces `<main>` content on visit. Place them as siblings of `<main>` in the layout.
- Prefer CSS-driven state over JS DOM manipulation when possible. For example, use `body:has([data-some-value="active"])` to conditionally show/hide elements elsewhere in the page, rather than querying the DOM from a Stimulus controller. CSS `:has()` selectors are powerful for cross-component state.
- Tool layout CSS: Use `auto` for topbar grid rows (not fixed px values) so they size naturally from the `tool-topbar` component. Avoid duplicate borders between adjacent elements (topbar `border-b` + content `border-t`).
- Icons: New icons must be added to `app/views/shared/_icon.html.erb` hash — SVG paths from Lucide
