import { Controller } from "@hotwired/stimulus"
import { pathOf, toolIdOf, toolFrame, frameAddress, sendFrameTo, hasUnfinishedWork, confirmClosing } from "services/tool_frame"
import { workspaceCommand, renameWorkspaceKeys } from "services/workspace_keys"

// The tiling workspace: every tool you open is a tile, and the tiles arrange
// themselves, the way a tiling window manager does it.
//
// A tile is the tool's own page in a frame, drawn without the sidebar
// (ApplicationController#tile?, tile_page_controller.js). A desktop is a tree: a tile, or a split
// with two halves, each of them a tile or a split again. A new tile halves the one
// you are on, side by side when that one is wide and stacked when it is tall.
//
// The tiles are all children of one element and get their place as left, top, width
// and height: a frame that moves in the page loads its page again, so no tile ever
// moves in the page. Tiles on another desktop stay loaded, out of sight.
//
// Which tiles, where, and on which desktop is kept in this browser, per person.
const GAP = 6
// Dragging a split never leaves a tile narrower or lower than this
const MIN_TILE = 220
// A new tile only halves one that leaves both halves at least this big
const ROOM_TO_SPLIT = { width: 340, height: 240 }
const GLIDE = "transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1)"
// What the plus and minus keys give a tile, or take from it
const RESIZE_STEP = 0.05
// How often the page around the tiles is drawn again while it is in view
const FRESHEN_EVERY_MS = 3 * 60 * 1000
// And never sooner after the last time: the menu closes with every tool opened from it
const FRESHEN_AT_MOST_EVERY_MS = 30 * 1000
const DESKS = [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ]

export default class extends Controller {
  static targets = ["tiles", "tileTemplate", "empty", "desks", "title", "menu", "hint", "status"]
  static values = { userId: Number, appName: String, start: String }

  connect() {
    // Never tiles inside a tile: a frame that ends up on this page (its tool is gone,
    // and the browser didn't say it was a frame) reports where it is and is dealt with
    // (inert: this controller does nothing for the rest of its life)
    this.inert = window.self !== window.top
    if (this.inert) return

    this.state = this.load()
    this.narrow = window.matchMedia("(max-width: 1023px)")
    this.still = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.handles = []
    // Tiles that are in the page already (the element outlives a morph refresh)
    this.elements = new Map()
    this.tilesTarget.querySelectorAll("[data-tile-id]").forEach((tile) => this.elements.set(tile.dataset.tileId, tile))
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
    this.listen(window, "command-palette:show", () => this.showMenu())
    this.listen(window, "command-palette:hide", () => this.closeMenu({ toTheTile: true }))
    // When a form on this page was sent, and which tool it was about (its settings), if any
    this.listen(document, "turbo:submit-end", (event) => {
      this.submitted = { at: performance.now(), toolId: toolIdOf(pathOf(event.target.action)) }
    })
    this.listen(document, "turbo:morph", () => this.refreshed())
    this.listen(document, "keydown", (event) => this.keyed(event), true)
    this.listen(window, "message", (event) => this.heard(event))
    this.listen(window, "pagehide", () => this.remember())
    this.listen(document, "visibilitychange", () => this.freshen())
    this.freshenTimer = setInterval(() => this.freshen(), FRESHEN_EVERY_MS)
    this.listen(window, "theme:change", (event) => this.tellAll("theme", { theme: event.detail }))
    this.listen(this.narrow, "change", () => this.arrange())

    this.sizes = new ResizeObserver(() => this.arrange())
    this.sizes.observe(this.tilesTarget)
    this.menuWatch = new MutationObserver(() => this.menuChanged())
    this.watchMenu()

    this.draw()
    this.arrive()
    this.grabFocus()
    this.hintTarget.hidden = this.seen("hint")
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

    this.listening.abort()
    this.sizes.disconnect()
    this.menuWatch.disconnect()
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

    const id = `t${this.state.next++}`
    this.state.tiles[id] = { url: path }
    const from = this.state.desk
    this.state.desk = this.insert(this.state.desk, id)
    this.desk.focus = id
    this.desk.alone = false
    this.save()
    this.draw({ glide: true })
    this.grabFocus()
    this.say(`${this.nameOf(id)} opened${this.state.desk === from ? "" : ` on desktop ${this.state.desk}`}`)
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
    const page = this.frameOf(id)?.contentWindow
    try {
      page.Turbo ? page.Turbo.visit(page.location.href, { action: "replace" }) : page.location.reload()
    } catch {
      // Not a page of ours to draw again
    }
  }

  // The page in a tile, loaded again
  reload(id) {
    const frame = this.frameOf(id)
    try {
      frame?.contentWindow.location.reload()
    } catch {
      if (frame) frame.src = this.state.tiles[id].url
    }
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
    return (this.state.desks[number] ||= { tree: null, focus: null, alone: false })
  }

  deskNumberOf(id) {
    return Object.keys(this.state.desks).find((number) => leaves(this.state.desks[number].tree).includes(id))
  }

  // Finds a new tile its place, and says on which desktop that is. It halves the tile
  // you are on, side by side when that is wide and stacked when it is tall. When
  // those halves would be too small it halves the biggest tile that has the room,
  // and when none has, it takes the next desktop with nothing on it.
  insert(number, id) {
    const desk = this.deskAt(number)
    if (!desk.tree) {
      desk.tree = { tile: id }
      return number
    }

    const rects = this.place(desk).tiles
    const tiles = leaves(desk.tree)
    const candidates = [ desk.focus, ...tiles.sort((a, b) => area(rects.get(b)) - area(rects.get(a))) ]
    for (const target of candidates) {
      const split = rects.has(target) && splitFor(rects.get(target))
      if (!split) continue

      const node = find(desk.tree, target)
      delete node.tile
      Object.assign(node, { split, ratio: 0.5, first: { tile: target }, second: { tile: id } })
      return number
    }

    const free = [ ...Array(9).keys() ].map((index) => (number + index) % 9 + 1).find((other) => !this.state.desks[other]?.tree)
    if (free) return this.insert(free, id)

    // Every desktop is in use and nothing has room: halve the one you are on anyway
    const target = tiles.includes(desk.focus) ? desk.focus : tiles.at(-1)
    const rect = rects.get(target)
    const node = find(desk.tree, target)
    delete node.tile
    Object.assign(node, { split: rect.height > rect.width ? "column" : "row", ratio: 0.5, first: { tile: target }, second: { tile: id } })
    return number
  }

  // The other half takes the room of both. Returns the tile that is nearest now.
  remove(desk, id) {
    if (desk.tree?.tile === id) return void (desk.tree = null)

    const parent = parentOf(desk.tree, id)
    if (!parent) return desk.focus

    const other = parent.first.tile === id ? parent.second : parent.first
    for (const key of Object.keys(parent)) delete parent[key]
    Object.assign(parent, other)
    return leaves(parent)[0]
  }

  // Where every tile of a desktop goes, and the gaps between them that can be dragged
  place(desk) {
    const room = this.room
    const tiles = new Map()
    const splits = []

    const put = (node, rect) => {
      if (node.tile) return tiles.set(node.tile, rect)

      const along = node.split === "row" ? "width" : "height"
      const from = node.split === "row" ? "x" : "y"
      const size = rect[along] - GAP
      const first = Math.round(size * node.ratio)

      put(node.first, { ...rect, [along]: first })
      put(node.second, { ...rect, [from]: rect[from] + first + GAP, [along]: size - first })
      splits.push({ node, room: rect, rect: { ...rect, [from]: rect[from] + first, [along]: GAP } })
    }

    if (desk.tree) put(desk.tree, room)
    return { tiles, splits }
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
    tile.append(toolFrame(this.state.tiles[id].url))
    this.tilesTarget.append(tile)
    this.elements.set(id, tile)
    this.nameTile(id)
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
    tile.querySelector("iframe").title = name
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
  // free one. Each shows the tools that are on it, by their icons from the menu. The
  // buttons stay the same ones, so the keyboard can stay on one.
  drawBar() {
    const used = Object.keys(this.state.desks).filter((number) => this.state.desks[number].tree).map(Number)
    const free = DESKS.find((number) => !used.includes(number))
    const shown = new Set([ ...used, this.state.desk, free ])

    if (this.desksTarget.children.length !== DESKS.length) {
      this.desksTarget.replaceChildren(...DESKS.map((number) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "workspace-desk"
        button.dataset.desk = number
        button.dataset.action = "click->workspace#deskClicked"
        return button
      }))
    }

    Array.from(this.desksTarget.children).forEach((button, index) => {
      const number = DESKS[index]
      const tiles = leaves(this.state.desks[number]?.tree)
      const names = tiles.map((id) => this.nameOf(id))

      button.hidden = !shown.has(number)
      button.setAttribute("aria-current", number === this.state.desk)
      button.toggleAttribute("data-empty", tiles.length === 0)
      button.title = names.join(", ")
      button.setAttribute("aria-label", names.length ? `Desktop ${number}: ${names.join(", ")}` : `Desktop ${number}`)
      button.replaceChildren(String(number), ...tiles.slice(0, 4).map((id) => this.iconOf(id)).filter(Boolean))
    })

    this.markMenu()

    // A tile says its own name; among several, the bar says which one you are on
    const desk = this.desk
    const count = leaves(desk.tree).length
    const title = this.state.tiles[desk.focus]?.title || ""
    this.titleTarget.textContent = count < 2 ? "" : desk.alone ? `${title} · ${count - 1} more behind it` : title
    document.title = title ? `${title} - ${this.appNameValue}` : this.appNameValue
  }

  // By the keyboard the keyboard stays on the button, to go on to the next desktop
  deskClicked(event) {
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

  // In the menu, a tool that is open says on which desktop, and needs no dot for
  // what is new in it: the ones that are loaded are seen
  markMenu() {
    document.querySelectorAll("[data-sidebar-tool-link][data-workspace-desk]").forEach((link) => {
      link.removeAttribute("data-workspace-desk")
      link.removeAttribute("title")
    })

    for (const [ id, tile ] of Object.entries(this.state.tiles)) {
      const link = this.menuLinkFor(tile.url)
      if (!link) continue

      link.dataset.workspaceDesk = this.deskNumberOf(id)
      link.title = `Open on desktop ${this.deskNumberOf(id)}`
      if (this.elements.has(id)) link.removeAttribute("data-unread")
    }
  }

  // ── Moving around ──

  focus(id) {
    if (!leaves(this.desk.tree).includes(id) || this.desk.focus === id) return

    this.desk.focus = id
    this.save()
    this.arrange()
    this.drawBar()
  }

  // The keyboard goes where the focus is
  grabFocus() {
    const frame = this.frameOf(this.desk.focus)
    frame ? frame.focus() : this.element.closest("main")?.focus()
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
    const rects = this.place(this.desk).tiles
    const from = rects.get(this.desk.focus)
    if (!from) return null

    const sideways = direction === "left" || direction === "right"
    const ahead = (rect) => ({
      left: from.x - (rect.x + rect.width),
      right: rect.x - (from.x + from.width),
      up: from.y - (rect.y + rect.height),
      down: rect.y - (from.y + from.height)
    })[direction]
    const shared = (rect) => sideways
      ? Math.min(from.y + from.height, rect.y + rect.height) - Math.max(from.y, rect.y)
      : Math.min(from.x + from.width, rect.x + rect.width) - Math.max(from.x, rect.x)

    return Array.from(rects.entries())
      .filter(([ id, rect ]) => id !== this.desk.focus && ahead(rect) >= 0 && shared(rect) > 0)
      .sort(([ , a ], [ , b ]) => ahead(a) - ahead(b) || shared(b) - shared(a))
      .map(([ id ]) => id)[0] || null
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
    this.say(`${this.nameOf(id)} moved to desktop ${this.state.desk}`)
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
    if (event.key === "F6") {
      event.preventDefault()
      return this.goToNext(event.shiftKey ? -1 : 1)
    }

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

    if (submitted?.toolId === toolId) {
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
    this.grabFocus()
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
    if (this.menu) this.menuWatch.observe(this.menu, { attributes: true, attributeFilter: [ "class" ] })
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
        if (message.pointer || this.frameOf(id) === document.activeElement) this.focus(id)
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
    this.frameOf(id).src = `/tools/${toolIdOf(tile.url)}`
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

  tellAll(what, details = {}) {
    for (const id of this.elements.keys()) {
      this.frameOf(id)?.contentWindow.postMessage({ tile: what, ...details }, location.origin)
    }
  }

  frameOf(id) {
    return this.elements.get(id)?.querySelector("iframe")
  }

  // ── Remembering ──

  get storageKey() {
    return `dobase:workspace:${this.userIdValue}`
  }

  load() {
    const fresh = { desk: 1, next: 1, desks: {}, tiles: {} }

    try {
      const kept = JSON.parse(localStorage.getItem(this.storageKey))
      if (!kept?.tiles || !kept?.desks) return fresh

      // Only ever a tool's page, and only tiles the trees still hold
      const tiles = {}
      for (const [ id, tile ] of Object.entries(kept.tiles)) {
        const url = pathOf(tile?.url)
        if (toolIdOf(url)) tiles[id] = { url, title: String(tile.title || "") }
      }
      const desks = {}
      const placedOnce = new Set()
      for (const [ number, desk ] of Object.entries(kept.desks)) {
        if (!/^[1-9]$/.test(number)) continue

        const tree = pruned(desk?.tree, tiles, placedOnce)
        const held = leaves(tree)
        desks[number] = { tree, focus: held.includes(desk.focus) ? desk.focus : held[0] || null, alone: Boolean(desk.alone) }
      }
      const placed = Object.values(desks).flatMap((desk) => leaves(desk.tree))
      for (const id of Object.keys(tiles)) if (!placed.includes(id)) delete tiles[id]

      const desk = Math.min(9, Math.max(1, Math.floor(Number(kept.desk)) || 1))
      const next = Math.max(Number(kept.next) || 1, ...Object.keys(tiles).map((id) => Number(id.slice(1)) + 1 || 1))
      return { desk, next, desks, tiles }
    } catch {
      return fresh
    }
  }

  save() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(this.state))
    } catch {
      // No storage (private browsing, a full disk): the tiles work, and are gone after a reload
    }
  }

  remember() {
    for (const id of this.elements.keys()) {
      const at = frameAddress(this.frameOf(id))
      if (at && this.state.tiles[id]) this.state.tiles[id].url = at
    }
    this.save()
  }
}

// The tiles of a tree, in the order they were split off
function leaves(node) {
  if (!node) return []
  return node.tile ? [ node.tile ] : [ ...leaves(node.first), ...leaves(node.second) ]
}

function find(node, id) {
  if (!node) return null
  return node.tile ? (node.tile === id ? node : null) : find(node.first, id) || find(node.second, id)
}

function parentOf(node, id) {
  if (!node || node.tile) return null
  if (node.first.tile === id || node.second.tile === id) return node
  return parentOf(node.first, id) || parentOf(node.second, id)
}

// A stored tree with only tiles that still exist, each of them once; a split that
// lost a half is the other half
function pruned(node, tiles, seen) {
  if (!node) return null
  if (node.tile) {
    if (!tiles[node.tile] || seen.has(node.tile)) return null
    seen.add(node.tile)
    return { tile: node.tile }
  }

  const first = pruned(node.first, tiles, seen)
  const second = pruned(node.second, tiles, seen)
  if (!first || !second) return first || second

  const ratio = Math.min(0.9, Math.max(0.1, Number(node.ratio) || 0.5))
  return { split: node.split === "column" ? "column" : "row", ratio, first, second }
}

function area(rect) {
  return rect ? rect.width * rect.height : 0
}

// How a tile of this size is halved for a new one beside it: along its longer side,
// or along the other when only that leaves two halves worth having. Nothing when
// neither does.
function splitFor(rect) {
  const row = (rect.width - GAP) / 2 >= ROOM_TO_SPLIT.width && rect.height >= ROOM_TO_SPLIT.height
  const column = (rect.height - GAP) / 2 >= ROOM_TO_SPLIT.height && rect.width >= ROOM_TO_SPLIT.width
  if (row && column) return rect.height > rect.width ? "column" : "row"
  return row ? "row" : column ? "column" : null
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
