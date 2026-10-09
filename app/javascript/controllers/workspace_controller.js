import { Controller } from "@hotwired/stimulus"
import { pathOf, toolIdOf, toolFrame, pageFrame, inPage, frameAddress, sendFrameTo, refreshFrame, reloadFrame, focusFrame, hasUnfinishedWork, confirmClosing } from "services/tool_frame"
import { workspaceCommand, renameWorkspaceKeys, workspaceKey } from "services/workspace_keys"
import { apiPost, csrfToken } from "services/api"
import { typing } from "services/typing"
import {
  GAP, MIN_TILE, DESKS, DESK_NAME_LENGTH, NOTHING_OPEN,
  deskAt, insert, remove, place, neighbour, cleaned, withChanges, parsed, deskOf, leaves, find, parentOf, deskName
} from "services/workspace_layout"

// The tiling workspace: every tool you open is a tile, and the tiles arrange
// themselves, the way a tiling window manager does it.
//
// A tile is the tool's own page in a frame, drawn without the sidebar
// (ApplicationController#tile?, tile_page_controller.js). A desktop is a tree: a tile, or a split
// with two halves, each of them a tile or a split again. A new tile halves the one
// you are on, side by side when that one is wide and stacked when it is tall.
//
// The keyboard is at one of two levels. On a tile (the tile itself has it): the arrows
// go from tile to tile, up to the bar and sideways on to the next desktop, Enter goes
// into the tool, Escape closes the tile. In a tool (its frame has it): the keys are
// the tool's, and Escape comes back out to the tile. The workspace's own keys
// (services/workspace_keys.js) work at both, and keep the level you are at.
//
// The tiles are all children of one element and get their place as left, top, width
// and height: a frame that moves in the page loads its page again, so no tile ever
// moves in the page. Tiles on another desktop stay loaded, out of sight.
//
// Which tiles, where, and on which desktop is kept per person on the server
// (WorkspaceLayout), so it is the same in every browser, with a copy in this browser
// to start from at once.
const GLIDE = "transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1)"
// What the plus and minus keys give a tile, or take from it
const RESIZE_STEP = 0.05
// How often the page around the tiles is drawn again while it is in view
const FRESHEN_EVERY_MS = 3 * 60 * 1000
// And never sooner after the last time: the menu closes with every tool opened from it
const FRESHEN_AT_MOST_EVERY_MS = 30 * 1000
// How many tools a desktop shows in the bar before it says "+2"
const TOOLS_IN_THE_BAR = 4
// A tool in sight is said to be seen this long after the last news of it: a busy chat
// is one message to the server, sent after its last message
const SEEN_AFTER_MS = 800
// The card about a desktop comes after the pointer has rested on it this long, and
// goes this long after it left
const CARD_AFTER_MS = 300
const CARD_GONE_AFTER_MS = 180
// A change is kept on the server this long after the last one: a split being dragged
// is one arrangement, not thirty
const KEEP_AFTER_MS = 600
// The kinds of tool that are part of this page. A room is a frame of its own: a call
// is better off in a document that nothing else draws in.
const IN_THIS_PAGE = [ "todos", "boards", "chat", "docs", "calendar", "files", "mail" ]

export default class extends Controller {
  static targets = ["tiles", "tileTemplate", "empty", "desks", "deskCard", "title", "menu", "hint", "status"]
  static values = { userId: Number, appName: String, start: String, kept: Object, revision: Number }

  connect() {
    // Never tiles inside a tile: a frame that ends up on this page (its tool is gone,
    // and the browser didn't say it was a frame) reports where it is and is dealt with
    // (inert: this controller does nothing for the rest of its life)
    this.inert = window.self !== window.top
    if (this.inert) return

    // Which of this person's pages a change came from, so its own are not news to it
    this.client = Math.random().toString(36).slice(2)
    // Where the arrangement is kept: this page's address, which the window no longer
    // has when it leaves for another page
    this.address = location.pathname
    this.state = this.load()
    this.narrow = window.matchMedia("(max-width: 1023px)")
    this.still = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.handles = []
    // Tiles that are in the page already (the element outlives a morph refresh)
    this.elements = new Map()
    this.tilesTarget.querySelectorAll("[data-tile-id]").forEach((tile) => this.elements.set(tile.dataset.tileId, tile))
    // The keyboard starts on the tile, not in its tool (see the two levels, above)
    this.held = true
    this.tilesTarget.querySelectorAll("[data-split]").forEach((handle) => handle.remove())

    this.listening = new AbortController()
    this.listen(document, "turbo:before-visit", (event) => this.visiting(event))
    this.listen(window, "workspace:open", (event) => { if (this.open(event.detail.url, { fresh: event.detail.fresh })) event.preventDefault() })
    this.listen(window, "workspace:command", (event) => this.run(event.detail))
    // The keys go with another modifier now (workspace_keys_controller.js chose here):
    // the tiles name them too
    this.listen(window, "workspace:keys-chosen", (event) => this.tellAll("keys", { chosen: event.detail }))
    // The search at the top of the menu (command_palette_controller.js) asks for the
    // menu when its key is pressed, and to have it away when something was picked
    // Down from the bar is back into the tile you were in (arrow_keys_controller.js on
    // this page says there is nothing further that way)
    this.listen(window, "arrow-keys:edge", (event) => {
      if (event.detail.side !== "down" || !this.element.contains(document.activeElement) || this.tilesTarget.contains(document.activeElement)) return

      event.preventDefault()
      this.grabFocus({ into: false })
    })
    this.listen(window, "command-palette:show", () => this.showMenu())
    this.listen(window, "command-palette:hide", () => this.closeMenu({ toTheTile: true }))
    // When a form on this page was sent, and which tool it was about (its settings), if any
    this.listen(document, "turbo:submit-end", (event) => {
      // (and from which tile, when the form was in one that is part of this page)
      const tile = event.target.closest?.(".tile-frame")?.closest("[data-tile-id]")?.dataset.tileId
      this.submitted = { at: performance.now(), toolId: toolIdOf(pathOf(event.target.action)), tile }
    })
    this.listen(document, "turbo:morph", () => this.refreshed())
    // The keyboard arrived on a tile itself, however it got there: that is the level it is at
    this.listen(this.tilesTarget, "focusin", (event) => {
      if (!event.target.matches("[data-tile-id]")) return

      this.held = true
      this.focus(event.target.dataset.tileId)
    })
    this.listen(document, "keydown", (event) => this.keyed(event), true)
    this.listen(window, "message", (event) => this.heard(event))
    // A tile that is part of this page (see inThisPage) says the same things
    // a tile in a frame of its own does, as events
    this.listen(this.tilesTarget, "tile:message", (event) => {
      const id = event.target.closest("[data-tile-id]")?.dataset.tileId
      if (id && this.state.tiles[id]) this.told(id, event.detail || {})
    })
    // A request from a tile that is part of this page is a tile's, and says where
    // that tile is: a form answered with "back where you came from" would be sent
    // to this page's address otherwise (ApplicationController#redirect_back_or_to)
    this.listen(document, "turbo:before-fetch-request", (event) => {
      const frame = event.target.closest?.(".tile-frame")
      if (!frame) return

      const { headers } = event.detail.fetchOptions
      headers["X-Tile"] = "1"
      const address = frameAddress(frame)
      if (address) headers["X-Tile-Address"] = address
    })
    this.listen(this.tilesTarget, "turbo:frame-missing", (event) => {
      if (!event.target.matches(".tile-frame")) return

      // The answer isn't that tile's page: signed out, or a page that is gone
      event.preventDefault()
      this.left(event.target.closest("[data-tile-id]").dataset.tileId)
    })
    this.listen(window, "pagehide", () => this.remember())
    // Another browser of this person's changed the arrangement (notifications_controller.js
    // hears it). A window nobody looks at takes it when it is looked at again.
    this.listen(window, "workspace:kept", (event) => {
      if (event.detail.by !== this.client && event.detail.revision > this.revision && !document.hidden) this.catchUp()
    })
    this.listen(window, "pageshow", (event) => { if (event.persisted) this.catchUp() })
    this.listen(window, "online", () => this.catchUp())
    this.listen(document, "visibilitychange", () => {
      if (!document.hidden) this.catchUp()
      this.freshen()
      // Back at the window: what is in sight is seen now
      this.drawBar()
    })
    this.freshenTimer = setInterval(() => this.freshen(), FRESHEN_EVERY_MS)
    this.listen(window, "theme:change", (event) => this.wearAll(event.detail))
    this.listen(this.narrow, "change", () => this.arrange())

    this.sizes = new ResizeObserver(() => this.arrange())
    this.sizes.observe(this.tilesTarget)
    this.menuWatch = new MutationObserver(() => this.menuChanged())
    // What is new in a tool, and a call that is on in a room, are marked in the menu
    // by whoever hears of them (notifications_controller.js); the bar shows it too
    this.seenSoon = new Map()
    this.newsWatch = new MutationObserver(() => this.newsChanged())
    this.watchMenu()

    for (const { id, tile, desk } of this.unplaced) {
      this.state.tiles[id] = tile
      this.insert(desk || this.state.desk, id)
    }
    this.draw()
    this.arrive()
    this.grabFocus()
    this.hintTarget.hidden = this.seen("hint")
    if (this.unsent) {
      this.write()
      this.keepSoon()
    }
  }

  // Things this browser has been told once
  seen(what) {
    try {
      return localStorage.getItem(`dobase:workspace:${what}`) === "seen"
    } catch {
      return true
    }
  }

  dismissHint() {
    this.hintTarget.hidden = true
    try {
      localStorage.setItem("dobase:workspace:hint", "seen")
    } catch {
      // No storage: it shows again next time
    }
    this.grabFocus()
  }

  // What this visit came for: a tool that was opened by its address (a link in a
  // mail, a bookmark: the page it would have been sends it here as ?open=), or, in a
  // workspace with nothing in it yet, the tool you were last on
  arrive() {
    const asked = new URLSearchParams(location.search).get("open")
    if (asked) {
      this.open(asked)
      history.replaceState(history.state, "", location.pathname)
    } else if (Object.keys(this.state.tiles).length === 0 && this.startValue) {
      this.open(this.startValue)
    }
  }

  disconnect() {
    if (this.inert) return

    // Leaving for another page of the app with a change still to send
    if (this.unsent) this.keep({ leaving: true })
    this.listening.abort()
    this.sizes.disconnect()
    this.menuWatch.disconnect()
    this.newsWatch.disconnect()
    clearTimeout(this.cardTimer)
    clearTimeout(this.keeping)
    clearInterval(this.freshenTimer)
  }

  listen(target, type, handler, capture = false) {
    target.addEventListener(type, handler, { capture, signal: this.listening.signal })
  }

  // ── Opening and closing ──

  // A tool that is open already is gone to; any other becomes a new tile beside the
  // one you are on. Asked for a tile of its own (Shift in the launcher, Alt and a
  // click on a link in a tile), a page gets one even when its tool is open: two
  // documents side by side.
  open(url, { fresh = false } = {}) {
    const path = pathOf(url)
    const toolId = toolIdOf(path)
    if (!toolId) return false

    const open = !fresh && Object.keys(this.state.tiles).find((id) => toolIdOf(this.state.tiles[id].url) === toolId)
    if (open) {
      this.goTo(open)
      // A page inside the tool (a card from a notification), not just the tool
      if (path !== `/tools/${toolId}` && path !== this.state.tiles[open].url) this.send(open, path)
      return true
    }

    const id = this.newId()
    this.state.tiles[id] = { url: path }
    const from = this.state.desk
    this.state.desk = this.insert(this.state.desk, id)
    this.desk.focus = id
    this.desk.alone = false
    this.save()
    this.draw({ glide: true })
    this.grabFocus({ into: true })
    this.say(`${this.nameOf(id)} opened${this.state.desk === from ? "" : ` on ${this.deskSaid(this.state.desk)}`}`)
    return true
  }

  async close(id) {
    const frame = this.frameOf(id)
    if (frame && hasUnfinishedWork(frame) && !(await confirmClosing())) return

    this.drop(id)
  }

  closeTile(event) {
    this.close(event.currentTarget.closest("[data-tile-id]").dataset.tileId)
  }

  // Takes a tile away without asking: its page is gone already, or was asked
  drop(id) {
    const desk = this.state.desks[this.deskNumberOf(id)]
    if (desk) {
      const next = this.remove(desk, id)
      if (desk.focus === id) {
        desk.focus = next || null
        // The tile that had the room to itself is gone: the others share it again
        desk.alone = false
      }
    }
    // The keyboard goes on to the next tile, unless it was somewhere else on the page
    const keyboardWasHere = this.tilesTarget.contains(document.activeElement) || document.activeElement === document.body

    this.say(`${this.nameOf(id)} closed`)
    delete this.state.tiles[id]
    this.leave(this.elements.get(id))
    this.elements.delete(id)
    this.save()
    this.draw({ glide: true })
    if (keyboardWasHere) this.grabFocus()
  }

  // A tile fades out where it was while the others take its room
  leave(tile) {
    if (!tile || tile.hidden || this.still.matches) return tile?.remove()

    tile.dataset.leaving = ""
    tile.inert = true
    tile.addEventListener("animationend", () => tile.remove(), { once: true })
    setTimeout(() => tile.remove(), 400)
  }

  // The page in a tile, drawn again where it is: its tool was renamed, or set up
  // otherwise, from the page around it. A visit to where it is already, which the
  // page takes as a refresh (a morph: what is open in it and how far it is scrolled
  // stay), and which it can refuse the way it refuses any other (an unsent mail).
  refresh(id) {
    refreshFrame(this.frameOf(id))
  }

  // The page in a tile, loaded again
  reload(id) {
    reloadFrame(this.frameOf(id), this.state.tiles[id].url)
  }

  send(id, path) {
    const frame = this.frameOf(id)
    if (!frame) return void (this.state.tiles[id].url = path)

    if (sendFrameTo(frame, path)) {
      this.state.tiles[id].url = path
      this.save()
    }
  }

  // ── The tree ──

  get desk() {
    return this.deskAt(this.state.desk)
  }

  deskAt(number) {
    return deskAt(this.state, number)
  }

  deskNumberOf(id) {
    return Object.keys(this.state.desks).find((number) => leaves(this.state.desks[number].tree).includes(id))
  }

  // Where a new tile goes, what is left when one is gone, and where each one is drawn
  // are worked out in services/workspace_layout.js, from the room there is here
  insert(number, id) {
    return insert(this.state, this.room, number, id)
  }

  remove(desk, id) {
    return remove(desk, id)
  }

  place(desk) {
    return place(desk, this.room)
  }

  get room() {
    const { width, height } = this.tilesTarget.getBoundingClientRect()
    return { x: GAP, y: 0, width: Math.max(0, width - 2 * GAP), height: Math.max(0, height - GAP) }
  }

  // ── Drawing ──

  // Brings the page in line with the state: a frame for every tile of this desktop
  // (other desktops load theirs when you first go there), each in its place
  draw({ glide = false } = {}) {
    for (const id of leaves(this.desk.tree)) {
      if (!this.elements.has(id)) this.addTile(id)
    }
    for (const [ id, tile ] of this.elements) {
      if (!this.state.tiles[id]) {
        tile.remove()
        this.elements.delete(id)
      }
    }

    this.arrange({ glide })
    this.drawBar()
  }

  addTile(id) {
    const tile = this.tileTemplateTarget.content.firstElementChild.cloneNode(true)
    tile.dataset.tileId = id
    tile.dataset.arriving = ""
    tile.addEventListener("animationend", () => delete tile.dataset.arriving, { once: true })
    const url = this.state.tiles[id].url
    tile.append(this.inThisPage(url) ? pageFrame(id, url) : toolFrame(url))
    this.tilesTarget.append(tile)
    this.elements.set(id, tile)
    this.nameTile(id)
  }

  // Every kind of tool but a room is drawn into this page (a <turbo-frame>:
  // services/tool_frame.js#pageFrame), not into a frame with a document of its own
  // (an <iframe>), which a room has
  inThisPage(url) {
    return IN_THIS_PAGE.includes(this.menuLinkFor(url)?.dataset.toolType)
  }

  // What a tile shows, by the name its page gave it, or its tool's name in the menu
  nameOf(id) {
    const tile = this.state.tiles[id]
    return tile?.title || this.menuLinkFor(tile?.url)?.dataset.toolName || "Tool"
  }

  // A tile, its frame and its close button are called after what is in it
  nameTile(id) {
    const tile = this.elements.get(id)
    if (!tile) return

    const name = this.nameOf(id)
    tile.setAttribute("aria-label", name)
    const frame = this.frameOf(id)
    if (frame && !inPage(frame)) frame.title = name
    tile.querySelector("button")?.setAttribute("aria-label", `Close ${name}`)
  }

  // Said to whoever can't see it happen
  say(what) {
    if (this.hasStatusTarget) this.statusTarget.textContent = what
  }

  arrange({ glide = false } = {}) {
    const desk = this.desk
    const { tiles, splits } = this.place(desk)
    // One tile with the room to itself: asked for, or the window is too narrow for more
    const alone = (desk.alone || this.narrow.matches) && tiles.has(desk.focus)
    const before = glide && !this.still.matches ? this.boxes() : null

    for (const [ id, tile ] of this.elements) {
      const rect = alone ? (id === desk.focus ? this.room : null) : tiles.get(id)

      tile.hidden = !rect
      tile.toggleAttribute("data-focused", id === desk.focus && tiles.size > 1 && !alone)
      id === desk.focus ? tile.setAttribute("aria-current", "true") : tile.removeAttribute("aria-current")
      if (rect) Object.assign(tile.style, px(rect))
    }

    this.emptyTarget.hidden = tiles.size > 0
    this.drawHandles(alone ? [] : splits)
    if (before) this.glide(before)
  }

  boxes() {
    const boxes = new Map()
    for (const [ id, tile ] of this.elements) {
      if (!tile.hidden) boxes.set(id, tile.getBoundingClientRect())
    }
    return boxes
  }

  // Tiles slide and stretch into their new place. They have their new size at once
  // and are drawn at the old one, shrinking the difference: the pages in them are
  // laid out once, not on every frame.
  glide(before) {
    for (const [ id, tile ] of this.elements) {
      const from = before.get(id)
      if (!from || tile.hidden) continue

      const to = tile.getBoundingClientRect()
      if (from.left === to.left && from.top === to.top && from.width === to.width && from.height === to.height) continue

      tile.style.transition = "none"
      tile.style.transform = `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width}, ${from.height / to.height})`
      requestAnimationFrame(() => {
        tile.style.transition = GLIDE
        tile.style.transform = ""
      })
    }
  }

  // The gaps between tiles, to drag
  drawHandles(splits) {
    while (this.handles.length < splits.length) {
      const handle = document.createElement("div")
      handle.className = "workspace-split"
      // For the pointer only: the keys resize the tile you are on
      handle.setAttribute("aria-hidden", "true")
      handle.addEventListener("pointerdown", (event) => this.startResize(event))
      this.tilesTarget.append(handle)
      this.handles.push(handle)
    }

    this.handles.forEach((handle, index) => {
      const split = splits[index]
      handle.hidden = !split
      if (!split) return

      handle.split = split
      handle.dataset.split = split.node.split
      Object.assign(handle.style, px(split.rect))
    })
  }

  startResize(event) {
    if (event.button !== 0) return
    event.preventDefault()

    const handle = event.currentTarget
    const { node, room } = handle.split
    const row = node.split === "row"
    const origin = this.tilesTarget.getBoundingClientRect()
    const size = (row ? room.width : room.height) - GAP
    const least = Math.min(MIN_TILE, size / 2)
    const dragging = new AbortController()

    const move = (pointer) => {
      const at = row ? pointer.clientX - origin.left - room.x : pointer.clientY - origin.top - room.y
      node.ratio = Math.max(least, Math.min(at - GAP / 2, size - least)) / size
      this.arrange()
    }
    const stop = () => {
      dragging.abort()
      delete this.tilesTarget.dataset.resizing
      this.save()
    }

    // The frames would take the pointer as soon as it is over them
    this.tilesTarget.dataset.resizing = ""
    handle.setPointerCapture(event.pointerId)
    handle.addEventListener("pointermove", move, { signal: dragging.signal })
    handle.addEventListener("pointerup", stop, { signal: dragging.signal })
    handle.addEventListener("pointercancel", stop, { signal: dragging.signal })
  }

  // The desktops that have something on them, the one you are on, and the first
  // free one. Each shows the tools that are on it by their icons from the menu: the
  // one you'd land on lit, a dot on one with something new in it that you aren't
  // looking at, a green one on a room with a call on. The buttons stay the same
  // ones, so the keyboard can stay on one, and one is only drawn again when what it
  // shows changed (a dot that just arrived makes a small entrance, once).
  drawBar() {
    const used = Object.keys(this.state.desks).filter((number) => this.state.desks[number].tree).map(Number)
    const free = DESKS.find((number) => !used.includes(number))
    // (one that was given a name stays in the bar while it is empty)
    const named = Object.keys(this.state.desks).filter((number) => this.state.desks[number].name).map(Number)
    const shown = new Set([ ...used, ...named, this.state.desk, free ])

    if (this.desksTarget.children.length !== DESKS.length) {
      this.desksTarget.replaceChildren(...DESKS.map((number) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "workspace-desk"
        button.dataset.desk = number
        button.dataset.action = "click->workspace#deskClicked dblclick->workspace#renameDesk pointerenter->workspace#showDeskCardSoon pointerleave->workspace#hideDeskCardSoon"
        return button
      }))
    }

    Array.from(this.desksTarget.children).forEach((button, index) => {
      const number = DESKS[index]
      const tiles = leaves(this.state.desks[number]?.tree).map((id) => this.about(id))
      const news = tiles.filter((tile) => tile.unread).map((tile) => tile.name)
      const calls = tiles.filter((tile) => tile.inCall).map((tile) => tile.name)
      const name = this.state.desks[number]?.name || ""
      const called = name ? `Desktop ${number}, ${name}` : `Desktop ${number}`

      button.hidden = !shown.has(number)
      button.setAttribute("aria-current", number === this.state.desk)
      button.toggleAttribute("data-empty", tiles.length === 0)
      button.toggleAttribute("data-unread", news.length > 0)
      button.setAttribute("aria-label", [
        tiles.length ? `${called}: ${tiles.map((tile) => tile.name).join(", ")}` : `${called}, nothing open`,
        news.length ? `New in ${news.join(", ")}` : null,
        calls.length ? `A call is on in ${calls.join(", ")}` : null
      ].filter(Boolean).join(". "))

      const drawn = JSON.stringify([ name, ...tiles.map((tile) => [ tile.id, tile.toolId, tile.unread, tile.inCall, tile.focused ]) ])
      if (button.dataset.drawn === drawn) return

      button.dataset.drawn = drawn
      const more = tiles.length - TOOLS_IN_THE_BAR
      button.replaceChildren(String(number), ...(name ? [ note(name, "workspace-desk-name") ] : []),
        ...tiles.slice(0, TOOLS_IN_THE_BAR).map((tile) => this.markOf(tile)), ...(more > 0 ? [ `+${more}` ] : []))
    })

    this.markMenu()

    // A tile says its own name; among several, the bar says which one you are on
    const desk = this.desk
    const count = leaves(desk.tree).length
    const title = this.state.tiles[desk.focus]?.title || ""
    this.titleTarget.textContent = count < 2 ? "" : desk.alone ? `${title} · ${count - 1} more behind it` : title
    document.title = title ? `${title} - ${this.appNameValue}` : this.appNameValue
  }

  // What the bar and the card about a desktop say of a tile
  about(id) {
    const tile = this.state.tiles[id]
    const toolId = toolIdOf(tile.url)
    const link = this.menuLinkFor(tile.url)
    const number = Number(this.deskNumberOf(id))

    return {
      id, toolId, name: this.nameOf(id), tool: link?.dataset.toolName || "",
      focused: this.state.desks[number]?.focus === id,
      unread: Boolean(link?.hasAttribute("data-unread")) && !this.inSight(id),
      inCall: Boolean(link?.closest("[data-tool-id]")?.hasAttribute("data-in-call"))
    }
  }

  // Whether you are looking at a tile: on the desktop you are on, not behind another
  // one that has the room to itself, in a window that is in front
  inSight(id) {
    const tile = this.elements.get(id)
    return Boolean(tile) && !tile.hidden && Number(this.deskNumberOf(id)) === this.state.desk && !document.hidden
  }

  // A tool's icon in a desktop's button, with what there is to say about it
  markOf(tile) {
    const mark = document.createElement("span")
    mark.className = "workspace-desk-tool"
    mark.toggleAttribute("data-focused", tile.focused)
    mark.toggleAttribute("data-unread", tile.unread)
    mark.toggleAttribute("data-in-call", tile.inCall)
    const icon = this.iconOf(tile.id)
    if (icon) mark.append(icon)
    return mark
  }

  // ── The card about a desktop: what is on it by name, to go straight to one ──

  showDeskCardSoon(event) {
    if (this.renamingDesk) return

    const button = event.currentTarget
    clearTimeout(this.cardTimer)
    this.cardTimer = setTimeout(() => this.showDeskCard(button), this.deskCardTarget.matches(":popover-open") ? 0 : CARD_AFTER_MS)
  }

  hideDeskCardSoon() {
    // (not from under a name that is being typed)
    if (this.renamingDesk) return

    clearTimeout(this.cardTimer)
    this.cardTimer = setTimeout(() => this.hideDeskCard(), CARD_GONE_AFTER_MS)
  }

  // The pointer went from the button into the card
  keepDeskCard() {
    clearTimeout(this.cardTimer)
  }

  hideDeskCard() {
    clearTimeout(this.cardTimer)
    if (this.hasDeskCardTarget && this.deskCardTarget.matches(":popover-open")) this.deskCardTarget.hidePopover()
  }

  showDeskCard(button, { renaming = false } = {}) {
    const number = Number(button.dataset.desk)
    const tiles = leaves(this.state.desks[number]?.tree).map((id) => this.about(id))
    const card = this.deskCardTarget
    const name = this.state.desks[number]?.name || ""

    const heading = document.createElement("div")
    heading.className = "workspace-desk-card-title"
    const key = document.createElement("kbd")
    key.className = "shortcut-key"
    key.textContent = workspaceKey(number)
    if (renaming) {
      heading.append(this.deskNameField(button, name), key)
    } else {
      const rename = document.createElement("button")
      rename.type = "button"
      rename.className = "workspace-desk-card-rename"
      rename.dataset.desk = number
      rename.dataset.action = "click->workspace#renameDesk"
      rename.title = "Rename this desktop"
      rename.setAttribute("aria-label", `Rename desktop ${number}`)
      rename.textContent = name || `Desktop ${number}`
      heading.append(rename, key)
    }

    const rows = tiles.map((tile) => {
      const row = document.createElement("div")
      row.className = "workspace-desk-card-row"
      row.toggleAttribute("data-unread", tile.unread)

      const go = document.createElement("button")
      go.type = "button"
      go.className = "workspace-desk-card-go"
      go.dataset.tileId = tile.id
      go.dataset.action = "click->workspace#goToTileOfCard"
      const name = document.createElement("span")
      name.className = "truncate"
      name.textContent = tile.name
      const icon = this.iconOf(tile.id)
      go.append(...(icon ? [ icon ] : []), name)
      // A page inside a tool has its own name: the tool's goes beside it
      if (tile.tool && tile.tool !== tile.name) go.append(note(tile.tool))
      if (tile.inCall) go.append(note("Call is on", "workspace-desk-card-call"))
      if (tile.unread) go.append(note("New", "workspace-desk-card-new"))

      const close = document.createElement("button")
      close.type = "button"
      close.className = "workspace-desk-card-close"
      close.dataset.tileId = tile.id
      close.dataset.action = "click->workspace#closeTileOfCard"
      close.setAttribute("aria-label", `Close ${tile.name}`)
      close.textContent = "×"

      row.append(go, close)
      return row
    })
    if (rows.length === 0) rows.push(note("Nothing open here yet. Go there and open a tool.", "workspace-desk-card-empty"))

    card.replaceChildren(heading, ...rows)
    const place = button.getBoundingClientRect()
    Object.assign(card.style, { left: `${place.left}px`, top: `${place.bottom + 6}px` })
    if (!card.matches(":popover-open")) card.showPopover()
  }

  // A desktop is a number until it is given a name: "Launch", "Mail". Asked for in
  // its card (the name there is a button), by a double click on it in the bar, or
  // from the menu's search ("Rename this desktop"). The card opens with a field.
  renameDesk(event) {
    const number = Number(event?.currentTarget?.dataset.desk) || this.state.desk
    const button = Array.from(this.desksTarget.children).find((desk) => Number(desk.dataset.desk) === number)
    if (!button) return

    clearTimeout(this.cardTimer)
    this.showDeskCard(button, { renaming: true })
  }

  // The field in a desktop's card. Enter and leaving it keep the name, Escape leaves
  // it as it was, and an empty one makes the desktop a number again.
  deskNameField(button, name) {
    const number = Number(button.dataset.desk)
    const field = document.createElement("input")
    field.type = "text"
    field.className = "workspace-desk-card-field"
    field.value = name
    field.maxLength = DESK_NAME_LENGTH
    field.placeholder = `Desktop ${number}`
    field.setAttribute("aria-label", `Name of desktop ${number}`)
    field.autocomplete = "off"

    this.renamingDesk = true
    const done = (keep) => {
      if (!this.renamingDesk) return

      this.renamingDesk = false
      if (keep) {
        this.deskAt(number).name = deskName(field.value)
        this.save()
        this.drawBar()
        this.say(this.deskAt(number).name ? `Desktop ${number} is called ${this.deskAt(number).name}` : `Desktop ${number} has no name`)
      }
      this.hideDeskCard()
      this.deskCardTarget.replaceChildren()
      this.grabFocus()
    }
    field.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== "Escape") return

      event.preventDefault()
      event.stopPropagation()
      done(event.key === "Enter")
    })
    field.addEventListener("blur", () => done(true))
    // Once it is in the page (the card is drawn after this returns)
    requestAnimationFrame(() => { field.focus(); field.select() })
    return field
  }

  // "Launch (desktop 2)", or "desktop 2" while it has no name
  deskSaid(number) {
    const name = this.state.desks[number]?.name
    return name ? `${name} (desktop ${number})` : `desktop ${number}`
  }

  goToTileOfCard(event) {
    this.hideDeskCard()
    this.goTo(event.currentTarget.dataset.tileId)
  }

  async closeTileOfCard(event) {
    const button = this.desksTarget.children[Number(this.deskNumberOf(event.currentTarget.dataset.tileId)) - 1]
    await this.close(event.currentTarget.dataset.tileId)
    // What is left on that desktop, while the pointer is still here
    if (button && this.deskCardTarget.matches(":popover-open")) this.showDeskCard(button)
  }

  // By the keyboard the keyboard stays on the button, to go on to the next desktop
  deskClicked(event) {
    this.hideDeskCard()
    this.goToDesk(event.currentTarget.dataset.desk, { keyboardStays: event.detail === 0 })
  }

  // A tool's icon as the menu draws it
  iconOf(id) {
    const link = this.menuLinkFor(this.state.tiles[id]?.url)
    const icon = link?.querySelector("svg, [aria-hidden='true']")?.cloneNode(true)
    if (!icon) return null

    icon.removeAttribute("width")
    icon.removeAttribute("height")
    icon.setAttribute("class", "workspace-desk-icon")
    return icon
  }

  menuLinkFor(url) {
    return document.querySelector(`[data-sidebar-tool-link][href="/tools/${toolIdOf(url)}"]`)
  }

  // In the menu, a tool that is open says on which desktop. A tool you are looking at
  // needs no dot for what is new in it: it is taken off, and the server is told you
  // saw it (a tile gets what is new live, without opening a page, which is how the
  // server would know). The menu's own button gets the dot for what is new in tools
  // that aren't open anywhere: with the menu away, nothing else would show it.
  markMenu() {
    document.querySelectorAll("[data-sidebar-tool-link][data-workspace-desk]").forEach((link) => {
      link.removeAttribute("data-workspace-desk")
      link.removeAttribute("data-in-sight")
      link.removeAttribute("title")
    })

    const open = new Set()
    for (const [ id, tile ] of Object.entries(this.state.tiles)) {
      const link = this.menuLinkFor(tile.url)
      if (!link) continue

      open.add(link)
      link.dataset.workspaceDesk = this.deskNumberOf(id)
      link.title = `Open on ${this.deskSaid(this.deskNumberOf(id))}`
      // What you are looking at: a notification about it makes no sound of its own
      // (notifications_controller.js#lookingAt; the tile makes its own, if any)
      if (this.inSight(id)) link.dataset.inSight = ""
      if (link.hasAttribute("data-unread") && this.inSight(id)) {
        link.removeAttribute("data-unread")
        this.sawTool(toolIdOf(tile.url))
      }
    }

    const elsewhere = Array.from(document.querySelectorAll("[data-sidebar-tool-link][data-unread]")).filter((link) => !open.has(link))
    this.menuTarget.toggleAttribute("data-unread", elsewhere.length > 0)
    this.menuTitle ||= this.menuTarget.title
    this.menuTarget.title = elsewhere.length ? `${this.menuTitle} · New in ${elsewhere.map((link) => link.dataset.toolName).join(", ")}` : this.menuTitle
  }

  sawTool(toolId) {
    clearTimeout(this.seenSoon.get(toolId))
    this.seenSoon.set(toolId, setTimeout(() => apiPost(`/tools/${toolId}/visit`), SEEN_AFTER_MS))
  }

  // Something new in a tool, or a call that began or ended: the bar is drawn again,
  // once for however many marks changed
  newsChanged() {
    if (this.newsDue) return

    this.newsDue = requestAnimationFrame(() => {
      this.newsDue = null
      this.drawBar()
    })
  }

  // ── Moving around ──

  focus(id) {
    if (!leaves(this.desk.tree).includes(id) || this.desk.focus === id) return

    this.desk.focus = id
    this.save()
    this.arrange()
    this.drawBar()
  }

  // The keyboard goes where the focus is, at the level it was at: into the tool, or
  // onto the tile itself
  grabFocus({ into = !this.held } = {}) {
    const tile = this.elements.get(this.desk.focus)
    if (!tile) return void this.element.closest("main")?.focus()

    this.held = !into
    into ? focusFrame(this.frameOf(this.desk.focus)) : tile.focus({ preventScroll: true })
  }

  // The arrows with the keyboard on a tile: to the tile on that side. Where there is
  // none, up is the bar, and sideways the next desktop that way with something on it.
  stepToward(direction) {
    const next = this.desk.alone || this.narrow.matches ? null : this.neighbour(direction)
    if (next) {
      this.focus(next)
      this.grabFocus({ into: false })
      return this.say(this.nameOf(next))
    }
    if (direction === "up") return this.desksTarget.children[this.state.desk - 1]?.focus()
    if (direction === "down") return

    const step = direction === "left" ? -1 : 1
    for (let number = this.state.desk + step; number >= 1 && number <= 9; number += step) {
      if (this.state.desks[number]?.tree) return this.goToDesk(number)
    }
  }

  // A key with the keyboard on a tile. True when it was one of the tile's.
  // In a tool, the keyboard stays in that tool. A tile with a document of its own
  // holds it by itself: whatever had the keyboard there and is gone leaves it with
  // that document. In a tile that is part of this page it would be left with this
  // page (a todo ticked off is drawn again, and what was pressed is no longer
  // there), and the next key would be the page's: the bar's, or another tile's. So
  // before any key is dealt with, a keyboard that is nowhere goes back into the tool
  // you are in.
  keepKeyboardInTheTool() {
    const active = document.activeElement
    const nowhere = !active || active === document.body || active === document.documentElement
    if (!nowhere || this.held || this.menuOpen || document.querySelector("dialog[open]")) return

    const frame = this.frameOf(this.desk.focus)
    if (inPage(frame)) focusFrame(frame)
  }

  tileKeyed(event) {
    const id = event.target.dataset.tileId
    const direction = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" }[event.key]
    if (!direction && ![ "Enter", " ", "Escape" ].includes(event.key)) return false

    event.preventDefault()
    event.stopPropagation()
    if (direction) {
      this.stepToward(direction)
    } else if (event.key === "Escape") {
      this.close(id)
    } else {
      this.focus(id)
      this.grabFocus({ into: true })
      this.say(`In ${this.nameOf(id)}. Escape comes back out.`)
    }
    return true
  }

  goToDesk(number, { keyboardStays = false } = {}) {
    number = Number(number)
    if (!number || number === this.state.desk) return

    const from = this.state.desk
    this.state.desk = number
    this.save()
    this.draw()
    this.slideIn(number > from ? "right" : "left")
    if (!keyboardStays) this.grabFocus()

    const names = leaves(this.desk.tree).map((id) => this.nameOf(id))
    this.say(names.length ? `Desktop ${number}: ${names.join(", ")}` : `Desktop ${number}, nothing open`)
  }

  // The tiles of the desktop you arrive on come in from the side it lies on
  slideIn(side) {
    if (this.still.matches) return

    for (const id of leaves(this.desk.tree)) {
      const tile = this.elements.get(id)
      if (!tile || tile.hidden) continue

      tile.dataset.sliding = side
      tile.addEventListener("animationend", () => delete tile.dataset.sliding, { once: true })
    }
  }

  // The tile on that side of the one you are on
  neighbour(direction) {
    return neighbour(this.desk, this.room, direction)
  }

  goToward(direction) {
    const next = this.neighbour(direction)
    if (!next) return

    this.focus(next)
    this.grabFocus()
  }

  // The tile you are on trades places with the one on that side
  moveToward(direction) {
    const other = this.neighbour(direction)
    if (!other) return

    const here = find(this.desk.tree, this.desk.focus)
    const there = find(this.desk.tree, other)
    there.tile = this.desk.focus
    here.tile = other
    this.save()
    this.arrange({ glide: true })
    this.say(`${this.nameOf(this.desk.focus)} moved ${direction}`)
  }

  // The tile you are on goes to another desktop, and you go with it
  takeToDesk(number) {
    const id = this.desk.focus
    if (!id || number === this.state.desk) return

    this.desk.focus = this.remove(this.desk, id) || null
    this.desk.alone = false
    this.state.desk = this.insert(number, id)
    this.desk.focus = id
    this.desk.alone = false
    this.save()
    this.draw()
    this.grabFocus()
    this.say(`${this.nameOf(id)} moved to ${this.deskSaid(this.state.desk)}`)
  }

  // The tile you are on gets more of the split it is in, or less
  resize(step) {
    const split = parentOf(this.desk.tree, this.desk.focus)
    if (!split) return

    const first = split.first.tile === this.desk.focus
    split.ratio = Math.min(0.85, Math.max(0.15, split.ratio + (first ? step : -step)))
    this.save()
    this.arrange({ glide: true })
  }

  // The tile alone, and back
  toggleAlone() {
    if (!this.desk.focus) return

    this.desk.alone = !this.desk.alone
    this.save()
    this.arrange({ glide: true })
    this.drawBar()
    this.say(this.desk.alone ? `${this.nameOf(this.desk.focus)} alone` : "All tiles side by side again")
  }

  // ── Keys ──

  // On this page; a page inside a tile hands the same keys on (heard, below)
  keyed(event) {
    if (event.key === "Escape" && this.menuOpen) return this.closeMenu()
    this.keepKeyboardInTheTool()
    // Backspace outside a field is "back" to some browsers, and back is in whichever
    // tile went somewhere last (tile_page_controller.js has the same)
    if (event.key === "Backspace" && !typing(event)) event.preventDefault()
    if (event.key === "F6") {
      event.preventDefault()
      return this.goToNext(event.shiftKey ? -1 : 1)
    }
    const plain = !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey
    if (plain && event.target.matches?.("[data-tile-id]") && this.tileKeyed(event)) return

    const command = workspaceCommand(event)
    if (!command) return

    event.preventDefault()
    event.stopPropagation()
    this.run(command)
  }

  run(command) {
    switch (command.name) {
      case "left": case "right": case "up": case "down":
        command.shift ? this.moveToward(command.name) : this.goToward(command.name)
        break
      case "desk":
        command.shift ? this.takeToDesk(command.desk) : this.goToDesk(command.desk)
        break
      case "close":
        if (this.desk.focus) this.close(this.desk.focus)
        break
      case "zoom":
        this.toggleAlone()
        break
      case "grow":
        this.resize(RESIZE_STEP)
        break
      case "shrink":
        this.resize(-RESIZE_STEP)
        break
      case "menu":
        this.toggleMenu()
        break
      case "reload":
        if (this.desk.focus) this.reload(this.desk.focus)
        break
      case "rename":
        // (after the menu has closed and given the keyboard back)
        setTimeout(() => this.renameDesk(), 50)
        break
    }
  }

  // The menu, with the keyboard in its search: what is picked there becomes a tile
  // (visiting, below). Through the page's own key for it, which empties the search.
  launch() {
    window.focus()
    document.querySelector("[data-hotkey='Mod+k']")?.click()
  }

  // ── The page around the tiles ──

  // Anything on this page that goes to a tool (the palette, the menu, a notification,
  // a tool that was just made) opens it as a tile instead
  visiting(event) {
    const address = new URL(event.detail.url, location.origin)
    if (address.origin !== location.origin || !toolIdOf(address.pathname)) return

    event.preventDefault()
    // A form on this page led here (Turbo follows its redirect right after it ends): a
    // tool was made, renamed or set up differently, and the menu and the bar still
    // say how it was. So do the tiles of a tool that was there already: all of them
    // are drawn again, and nobody has to load the window again to see it.
    const submitted = this.submitted && performance.now() - this.submitted.at < 1000 ? this.submitted : null
    const toolId = toolIdOf(address.pathname)

    const from = submitted?.tile && this.state.tiles[submitted.tile] ? submitted.tile : null
    if (from && toolIdOf(this.state.tiles[from].url) === toolId) {
      // A form in a tile of this page was sent, and this is where it leads (a mail sent
      // leads to its conversation): that tile goes there, or is drawn again when it
      // is there already
      const path = address.pathname + address.search
      frameAddress(this.frameOf(from)) === path ? this.refresh(from) : this.send(from, path)
    } else if (submitted?.toolId === toolId) {
      // Its settings, not a wish to go there: you stay where you are
      for (const [ id, tile ] of Object.entries(this.state.tiles)) {
        if (toolIdOf(tile.url) === toolId && this.elements.has(id)) this.refresh(id)
      }
    } else {
      this.open(address.href)
    }
    // The keyboard goes to the tile that was asked for, not back to the menu's button
    this.closeMenu({ toTheTile: true })
    if (submitted) this.freshen({ evenIfBusy: true })
  }

  // To a tile that is open, on whatever desktop it is
  goTo(id) {
    this.goToDesk(this.deskNumberOf(id))
    this.focus(id)
    this.grabFocus({ into: true })
  }

  // The server drew this page again (a morph, which leaves the tiles alone): the bar
  // is ours to fill, and a tile whose tool is no longer in the menu has lost it
  refreshed() {
    this.hintTarget.hidden = this.seen("hint")

    const tools = new Set(Array.from(document.querySelectorAll("[data-sidebar-tool-link]")).map((link) => toolIdOf(link.getAttribute("href"))))
    for (const [ id, tile ] of Object.entries(this.state.tiles)) {
      if (tools.size > 0 && !tools.has(toolIdOf(tile.url))) this.drop(id)
    }
    this.arrange()
    this.drawBar()
    this.watchMenu()
    this.menuChanged()
  }

  // The sidebar is the menu here: in over the tiles with the keyboard in its search,
  // and out again with the keyboard back where it came from. The launcher's key, the
  // menu's key and the logo all open this one menu.
  get menu() {
    return document.querySelector("[data-mobile-sidebar-target='sidebar']")
  }

  get menuOpen() {
    return this.menu?.classList.contains("open")
  }

  toggleMenu() {
    this.menuOpen ? this.closeMenu() : this.launch()
  }

  showMenu() {
    if (!this.menuOpen) this.menuTarget.click()
  }

  // The menu's button: pressed with the keyboard on it, the keyboard comes back to it
  menuAsked(event) {
    this.menuReturnsToButton = event.isTrusted && event.detail === 0
  }

  closeMenu({ toTheTile = false } = {}) {
    if (!this.menuOpen) return

    if (toTheTile) this.menuReturnsToButton = false
    const around = this.element.closest("[data-controller~='mobile-sidebar']")
    this.application.getControllerForElementAndIdentifier(around, "mobile-sidebar")?.close()
  }

  // Others open and close the menu too (its button, a click beside it), so what
  // follows from that hangs on the menu itself
  watchMenu() {
    this.menuWatch.disconnect()
    this.newsWatch.disconnect()
    if (!this.menu) return

    this.menuWatch.observe(this.menu, { attributes: true, attributeFilter: [ "class" ] })
    this.newsWatch.observe(this.menu, { subtree: true, attributes: true, attributeFilter: [ "data-unread", "data-in-call" ] })
  }

  // In: its button says so, the tiles under it are out of reach, the keyboard is on
  // the first tool. Out: the keyboard is back, and the page around the tiles is drawn
  // again.
  menuChanged() {
    const open = Boolean(this.menuOpen)
    if (open === Boolean(this.menuWasOpen)) return

    this.menuWasOpen = open
    this.menuTarget.setAttribute("aria-expanded", open)
    this.tilesTarget.inert = open
    // Its search starts empty, coming and going
    window.dispatchEvent(new CustomEvent("workspace:menu", { detail: { open } }))
    if (open) {
      (this.menu.querySelector("[data-command-palette-target='input']") || this.menu.querySelector("[data-sidebar-tool-link]"))?.focus()
    } else {
      this.menuReturnsToButton ? this.menuTarget.focus() : this.grabFocus()
      this.menuReturnsToButton = false
      this.freshen()
    }
  }

  // The menu and the launcher were drawn when this page was, which can be hours ago:
  // the page around the tiles is drawn again now and then, when the menu closes and
  // when you come back to the window. Never while a menu or a dialog is open: that
  // closes them under your hands.
  //
  // Not a Turbo visit: one that fails (no network yet after the lid opens, a server
  // error, new assets after a deploy) loads the whole page again or replaces it, and
  // every tile with it. The page is fetched here, and only an answer that is this
  // page is morphed in (which leaves the tiles alone).
  async freshen({ evenIfBusy = false } = {}) {
    if (this.freshening || !(evenIfBusy || this.calm)) return
    if (!evenIfBusy && performance.now() - this.freshenedAt < FRESHEN_AT_MOST_EVERY_MS) return

    this.freshening = true
    try {
      const response = await fetch(location.href, { headers: { Accept: "text/html" } })
      if (!response.ok || response.redirected) return

      const fresh = new DOMParser().parseFromString(await response.text(), "text/html")
      if (!fresh.querySelector("[data-controller~='workspace']") || tracked(fresh) !== tracked(document)) return
      if (!(evenIfBusy || this.calm)) return

      Turbo.morphBodyElements(document.body, fresh.body)
      this.freshenedAt = performance.now()
    } catch {
      // No network: next time
    } finally {
      this.freshening = false
    }
  }

  get calm() {
    return !document.hidden && !this.menuOpen && !document.querySelector("dialog[open], :popover-open")
  }

  // ── What the pages in the tiles say (tile_page_controller.js) ──

  heard(event) {
    if (event.origin !== location.origin) return

    const id = Array.from(this.elements.keys()).find((tile) => this.frameOf(tile)?.contentWindow === event.source)
    const message = event.data || {}
    if (!id || !message.tile) return

    this.told(id, message)
  }

  // What a tile says about itself, and asks of the page around it
  told(id, message) {
    const here = (frame) => inPage(frame) ? frame.contains(document.activeElement) : frame === document.activeElement

    switch (message.tile) {
      case "location": {
        const path = pathOf(message.url)
        if (!toolIdOf(path)) return this.strayed(id)

        Object.assign(this.state.tiles[id], { url: path, title: titleOf(message.title, this.appNameValue), strayed: false })
        this.nameTile(id)
        this.save()
        this.drawBar()
        break
      }
      case "focus":
        // A click in a tile is where you are. The keyboard arriving in one only counts
        // while it is still there: a dialog that closes hands it back to the tile it
        // came from for a moment, and that tile says so after the launcher has
        // already opened another.
        if (message.pointer || here(this.frameOf(id))) {
          this.focus(id)
          // The keyboard is in the tool now
          this.held = false
        }
        // A click that something in the tile kept to itself (a card that can be dragged
        // takes the press for the drag) moves no keyboard: the tile is lit and the keys
        // still go to the one you were in. The keyboard goes along with the click.
        if (message.pointer && !here(this.frameOf(id)) && !this.menuOpen && !document.querySelector("dialog[open]")) this.grabFocus({ into: true })
        break
      case "command":
        this.run(message.command)
        break
      case "open":
        this.open(message.url, { fresh: true })
        break
      case "launcher":
        this.launch()
        break
      case "notifications":
        window.focus()
        this.element.querySelector("[data-notifications-target='trigger']")?.click()
        break
      case "next":
        this.goToNext(message.back ? -1 : 1)
        break
      case "escape":
        // Escape in a tool with nothing left to let go of: out of the tool, onto its tile
        this.focus(id)
        this.grabFocus({ into: false })
        // (the key was pressed in the tile's page, which this page didn't see)
        this.elements.get(id)?.setAttribute("data-keyboard-focus", "")
        this.say(`${this.nameOf(id)}: Enter goes in, Escape closes it`)
        break
      case "keys":
        // Chosen in that tile's own shortcuts dialog: here and in the other tiles too
        renameWorkspaceKeys(message.chosen || {})
        this.tellAll("keys", { chosen: message.chosen })
        break
      case "gone":
        this.left(id)
        break
    }
  }

  // A tile that was sent away from its tool: a page in it that no longer exists (a
  // card someone deleted) sends you to the start, which is no tool's page. It goes
  // back to its tool once; a tool that is gone itself sends it away again, and then
  // there is nothing to keep.
  strayed(id) {
    const tile = this.state.tiles[id]
    if (tile.strayed) return this.drop(id)

    tile.strayed = true
    this.frameOf(id).setAttribute("src", `/tools/${toolIdOf(tile.url)}`)
  }

  // A tile shows a page that isn't the app's. Signed out (somewhere else, or the
  // session ended) is the usual reason: then this page goes to sign in, and the tiles
  // are all still there afterwards. Anything else, and the tile has nothing to show.
  async left(id) {
    const here = await fetch(location.href, { headers: { Accept: "text/html" } }).catch(() => null)
    if (here && new URL(here.url).pathname !== location.pathname) return window.location.reload()

    this.drop(id)
  }

  // F6: on to the next tile, with Shift back to the one before
  goToNext(step = 1) {
    const tiles = leaves(this.desk.tree)
    const next = tiles[(tiles.indexOf(this.desk.focus) + step + tiles.length) % tiles.length]
    if (next) this.focus(next)
    this.grabFocus()
  }

  // A new theme goes on every tile in the same moment as on this page. It is said to
  // each tile's window directly, which hears it at once: a message arrives a task
  // later, and with a frame drawn in between the tiles would change one after the
  // other. The message goes as well, for a frame that can't be reached yet (it is
  // still loading); a tile that has the theme already leaves it at that.
  wearAll(theme) {
    // (a tile that is part of this page wears what this page wears)
    const frames = Array.from(this.elements.keys(), (id) => this.frameOf(id)).filter((frame) => frame && !inPage(frame))
    for (const frame of frames) {
      try {
        const page = frame.contentWindow
        page.dispatchEvent(new page.CustomEvent("workspace:theme", { detail: theme }))
      } catch {
        // Not a page of the app's (an error page): the message below is all it gets
      }
      frame.contentWindow?.postMessage({ tile: "theme", theme }, location.origin)
    }
  }

  tellAll(what, details = {}) {
    for (const id of this.elements.keys()) {
      this.frameOf(id)?.contentWindow?.postMessage({ tile: what, ...details }, location.origin)
    }
  }

  frameOf(id) {
    return this.elements.get(id)?.querySelector(":scope > iframe, :scope > .tile-frame")
  }

  // ── Remembering ──
  //
  // The arrangement is this person's, not this browser's: it is kept on the server
  // (WorkspaceLayout), every browser starts from what is kept there, and a change in
  // one is taken over by the others. A copy stays in this browser, to start from
  // without waiting and for a window too narrow for tiles (workspace_gate.js).
  //
  // Each arrangement kept has a revision. A change is sent with the revision it was
  // made from, and refused when another browser changed things since. This one then
  // takes what is kept and does again on it what was changed here (a tile opened or
  // closed, a desktop rearranged or named), rather than lay its older arrangement
  // over the other browser's, or lose what was just done here.

  get storageKey() {
    return `dobase:workspace:${this.userIdValue}`
  }

  // A tile's name is its own in every browser this person has open
  newId() {
    let id
    do id = `t${Math.random().toString(36).slice(2, 9)}`
    while (this.state.tiles[id])
    return id
  }

  // What the server keeps. This browser's copy says the same, unless it holds a
  // change that never got there (the page left before it was sent, or while it was
  // on its way): then that change is done again on what is kept.
  load() {
    const theirs = this.revisionValue > 0 ? cleaned(this.keptValue) : null
    this.revision = this.revisionValue
    this.keptBody = theirs ? JSON.stringify(theirs) : null
    this.unplaced = []

    let state = theirs
    try {
      const copy = JSON.parse(localStorage.getItem(this.storageKey))
      const mine = cleaned(copy)
      if (mine && !theirs) {
        state = mine
      } else if (mine && copy.unsent) {
        if (Number(copy.revision) === this.revision) {
          state = mine
        } else {
          const next = withChanges(cleaned(parsed(copy.base)) || NOTHING_OPEN, mine, theirs)
          state = cleaned(next)
          // Tiles the tree of their desktop doesn't hold get a place once there is a room to measure
          this.unplaced = Object.keys(next.tiles).filter((id) => !state.tiles[id])
            .map((id) => ({ id, tile: next.tiles[id], desk: Number(deskOf(theirs, id) || deskOf(mine, id)) }))
        }
      }
    } catch {
      // No storage, or nothing readable in it
    }

    this.unsent = Boolean(state) && (JSON.stringify(state) !== this.keptBody || this.unplaced.length > 0)
    return state || structuredClone(NOTHING_OPEN)
  }

  save() {
    this.unsent = true
    this.write()
    this.keepSoon()
  }

  // The copy in this browser: the arrangement, the revision and arrangement on the
  // server it was made from, and whether it holds a change still to send
  write() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({ ...this.state, revision: this.revision, base: this.keptBody, unsent: this.unsent }))
    } catch {
      // No storage (private browsing, a full disk): the server keeps it all the same
    }
  }

  keepSoon() {
    clearTimeout(this.keeping)
    this.keeping = setTimeout(() => this.keep(), KEEP_AFTER_MS)
  }

  // Sends the arrangement to the server, one at a time. `leaving` is the last one of
  // a page that is going: the browser sends it on after the page is gone.
  async keep({ leaving = false } = {}) {
    clearTimeout(this.keeping)
    if (this.keepingNow) return void (this.keepAgain = true)

    const state = cleaned(this.state)
    const body = JSON.stringify(state)
    if (body === this.keptBody) {
      this.unsent = false
      return this.write()
    }

    this.keepingNow = true
    try {
      const response = await fetch(this.address, {
        method: "PATCH",
        keepalive: leaving,
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        body: JSON.stringify({ state, revision: this.revision, client: this.client })
      })
      if (response.ok) {
        this.revision = (await response.json()).revision
        this.keptBody = body
        this.unsent = JSON.stringify(cleaned(this.state)) !== body
        this.write()
      } else if (response.status === 409) {
        this.adopt(await response.json(), { refused: true })
      }
      // Anything else (signed out, a server in trouble): still unsent, and tried
      // again with the next change or when the window is looked at again
    } catch {
      // No network: the same
    } finally {
      this.keepingNow = false
      if (this.keepAgain) {
        this.keepAgain = false
        this.keep()
      }
    }
  }

  // Back at this window, or told of a change elsewhere: what is kept now. A change
  // of its own goes first, and is taken or refused there.
  async catchUp() {
    if (this.unsent) await this.keep()
    if (this.unsent) return

    try {
      const response = await fetch(this.address, { headers: { Accept: "application/json" } })
      if (response.ok && !response.redirected) this.adopt(await response.json())
    } catch {
      // No network: when it is back
    }
  }

  // Takes over the arrangement another browser of this person's made: tiles it closed
  // go, tiles it opened come, a tile it took to another page goes there, and
  // everything gets the place it has there. When a change made here was refused
  // because of it, that change is done again on top. A tile with unfinished work in
  // it (an unsent mail, a call) stays as it is here, whatever the other browser did
  // with it.
  adopt({ revision, state }, { refused = false } = {}) {
    // Not news, or something changed here while this was on its way: sending that
    // finds out what to make of the two
    if (!refused && (revision <= this.revision || this.unsent)) return

    const theirs = cleaned(state)
    const base = parsed(this.keptBody) || NOTHING_OPEN
    const mine = cleaned(this.state)
    this.revision = revision
    this.keptBody = theirs ? JSON.stringify(theirs) : null
    // Nothing kept there after all: what is here goes there
    if (!theirs) return this.keepSoon()
    if (this.keptBody === JSON.stringify(mine)) {
      this.unsent = false
      return this.write()
    }

    const next = refused ? withChanges(base, mine, theirs) : theirs
    const keyboardWasHere = this.tilesTarget.contains(document.activeElement) || document.activeElement === document.body
    // Tiles of both that the tree of their desktop doesn't hold (opened there, on a
    // desktop that was rearranged here) get a place on it after the rest
    const placed = new Set(Object.values(next.desks).flatMap((desk) => leaves(desk.tree)))
    const loose = Object.keys(next.tiles).filter((id) => !placed.has(id))
    this.state = cleaned(next)

    for (const [ id, tile ] of Array.from(this.elements)) {
      const frame = this.frameOf(id)
      const there = this.state.tiles[id]
      if (!there) {
        if (hasUnfinishedWork(frame)) {
          next.tiles[id] = mine.tiles[id]
          loose.push(id)
        } else {
          this.leave(tile)
          this.elements.delete(id)
        }
      } else if (there.url !== mine.tiles[id]?.url && there.url !== frameAddress(frame)) {
        if (hasUnfinishedWork(frame) || !sendFrameTo(frame, there.url)) Object.assign(there, mine.tiles[id])
      }
    }
    for (const id of loose) {
      this.state.tiles[id] = next.tiles[id]
      this.insert(Number(deskOf(theirs, id) || deskOf(mine, id)) || this.state.desk, id)
    }

    this.unsent = JSON.stringify(cleaned(this.state)) !== this.keptBody
    this.write()
    this.draw({ glide: true })
    for (const id of this.elements.keys()) this.nameTile(id)
    if (keyboardWasHere && this.calm) this.grabFocus()
    this.say("Arranged as in your other window")
    if (this.unsent) this.keepSoon()
  }

  // A page that is going writes down where every tile is, and sends it on
  remember() {
    let moved = false
    for (const id of this.elements.keys()) {
      const at = frameAddress(this.frameOf(id))
      if (at && this.state.tiles[id] && this.state.tiles[id].url !== at) {
        this.state.tiles[id].url = at
        moved = true
      }
    }
    if (moved) this.unsent = true
    this.write()
    if (this.unsent) this.keep({ leaving: true })
  }
}

// A few words beside a tile's name in the card about a desktop
function note(text, className = "workspace-desk-card-note") {
  const words = document.createElement("span")
  words.className = className
  words.textContent = text
  return words
}

function px(rect) {
  return { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px` }
}

// The scripts and styles a page was built with: other ones mean a deploy since
function tracked(page) {
  return Array.from(page.querySelectorAll("head [data-turbo-track='reload']"), (asset) => asset.getAttribute("src") || asset.getAttribute("href")).join(" ")
}

// "Team Chat" from "Team Chat - Dobase"
function titleOf(title, appName) {
  const suffix = ` - ${appName}`
  return title?.endsWith(suffix) ? title.slice(0, -suffix.length) : title || ""
}
