import { Controller } from "@hotwired/stimulus"
import { pathOf, toolIdOf, toolFrame, frameAddress, sendFrameTo, hasUnfinishedWork, confirmClosing } from "services/tool_frame"
import { workspaceCommand } from "services/workspace_keys"

// The tiling workspace: every tool you open is a tile, and the tiles arrange
// themselves, the way a tiling window manager does it.
//
// A tile is the tool's own page in a frame, drawn without the sidebar, as beside
// another tool (side_pane_controller.js). A desktop is a tree: a tile, or a split
// with two halves, each of them a tile or a split again. A new tile halves the one
// you are on, side by side when that one is wide and stacked when it is tall.
//
// The tiles are all children of one element and get their place as left, top, width
// and height: a frame that moves in the page loads its page again, so no tile ever
// moves in the page. Tiles on another desktop stay loaded, out of sight.
//
// Which tiles, where, and on which desktop is kept in this browser, per person.
const GAP = 6
// A split never leaves a tile narrower or lower than this
const MIN_TILE = 220
const GLIDE = "transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1)"
// What the plus and minus keys give a tile, or take from it
const RESIZE_STEP = 0.05

export default class extends Controller {
  static targets = ["tiles", "tileTemplate", "empty", "desks", "title", "menu"]
  static values = { userId: Number, appName: String }

  connect() {
    this.state = this.load()
    this.narrow = window.matchMedia("(max-width: 1023px)")
    this.still = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.handles = []
    // Tiles that are in the page already (the element outlives a morph refresh)
    this.elements = new Map()
    this.tilesTarget.querySelectorAll("[data-tile-id]").forEach((tile) => this.elements.set(tile.dataset.tileId, tile))

    this.listening = new AbortController()
    this.listen(document, "turbo:before-visit", (event) => this.visiting(event))
    this.listen(document, "turbo:submit-end", () => { this.submittedAt = performance.now() })
    this.listen(document, "turbo:morph", () => this.refreshed())
    this.listen(document, "keydown", (event) => this.keyed(event), true)
    this.listen(window, "message", (event) => this.heard(event))
    this.listen(window, "pagehide", () => this.remember())
    this.listen(window, "theme:change", (event) => this.tellAll("theme", { theme: event.detail }))
    this.listen(this.narrow, "change", () => this.arrange())

    this.sizes = new ResizeObserver(() => this.arrange())
    this.sizes.observe(this.tilesTarget)

    this.draw()
    this.grabFocus()
  }

  disconnect() {
    this.listening.abort()
    this.sizes.disconnect()
  }

  listen(target, type, handler, capture = false) {
    target.addEventListener(type, handler, { capture, signal: this.listening.signal })
  }

  // ── Opening and closing ──

  // A tool that is open already is gone to; any other becomes a new tile beside the
  // one you are on
  open(url) {
    const path = pathOf(url)
    const toolId = toolIdOf(path)
    if (!toolId) return false

    const open = Object.keys(this.state.tiles).find((id) => toolIdOf(this.state.tiles[id].url) === toolId)
    if (open) {
      this.goToDesk(this.deskNumberOf(open))
      this.focus(open)
      // A page inside the tool (a card from a notification), not just the tool
      if (path !== `/tools/${toolId}` && path !== this.state.tiles[open].url) this.send(open, path)
      return true
    }

    const id = `t${this.state.next++}`
    this.state.tiles[id] = { url: path }
    this.insert(this.desk, id)
    this.desk.focus = id
    this.desk.alone = false
    this.save()
    this.draw({ glide: true })
    this.grabFocus()
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
    delete this.state.tiles[id]
    this.elements.get(id)?.remove()
    this.elements.delete(id)
    this.save()
    this.draw({ glide: true })
    this.grabFocus()
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
    return (this.state.desks[this.state.desk] ||= { tree: null, focus: null, alone: false })
  }

  deskNumberOf(id) {
    return Object.keys(this.state.desks).find((number) => leaves(this.state.desks[number].tree).includes(id))
  }

  // Halves the tile you are on: side by side when it is wide, stacked when it is tall
  insert(desk, id) {
    if (!desk.tree) return void (desk.tree = { tile: id })

    const tiles = leaves(desk.tree)
    const target = tiles.includes(desk.focus) ? desk.focus : tiles.at(-1)
    const rect = this.place(desk).tiles.get(target)
    const node = find(desk.tree, target)

    delete node.tile
    Object.assign(node, {
      split: rect.height > rect.width ? "column" : "row",
      ratio: 0.5,
      first: { tile: target },
      second: { tile: id }
    })
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
    tile.append(toolFrame(this.state.tiles[id].url, "workspace-tile"))
    this.tilesTarget.append(tile)
    this.elements.set(id, tile)
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
      handle.setAttribute("role", "separator")
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
      handle.setAttribute("aria-orientation", split.node.split === "row" ? "vertical" : "horizontal")
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

  // The desktops that have something on them, the one you are on, and the next free one
  drawBar() {
    const used = Object.keys(this.state.desks).filter((number) => this.state.desks[number].tree).map(Number)
    const last = Math.min(9, Math.max(this.state.desk, ...used, 0) + 1)

    this.desksTarget.replaceChildren(...Array.from({ length: last }, (_, index) => {
      const number = index + 1
      const button = document.createElement("button")
      button.type = "button"
      button.className = "workspace-desk"
      button.textContent = number
      button.setAttribute("aria-label", `Desktop ${number}`)
      button.setAttribute("aria-current", number === this.state.desk)
      button.toggleAttribute("data-empty", !used.includes(number))
      button.addEventListener("click", () => this.goToDesk(number))
      return button
    }))

    // What is open as a tile is seen: no dot for it in the menu
    for (const tile of Object.values(this.state.tiles)) {
      document.querySelector(`[data-sidebar-tool-link][href="/tools/${toolIdOf(tile.url)}"]`)?.removeAttribute("data-unread")
    }

    const title = this.state.tiles[this.desk.focus]?.title || ""
    this.titleTarget.textContent = title
    document.title = title ? `${title} - ${this.appNameValue}` : this.appNameValue
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

  goToDesk(number) {
    number = Number(number)
    if (!number || number === this.state.desk) return

    this.state.desk = number
    this.save()
    this.draw()
    this.grabFocus()
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
  }

  // The tile you are on goes to another desktop, and you go with it
  takeToDesk(number) {
    const id = this.desk.focus
    if (!id || number === this.state.desk) return

    this.desk.focus = this.remove(this.desk, id) || null
    this.desk.alone = false
    this.state.desk = number
    this.insert(this.desk, id)
    this.desk.focus = id
    this.desk.alone = false
    this.save()
    this.draw()
    this.grabFocus()
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
  }

  // ── Keys ──

  // On this page; a page inside a tile hands the same keys on (heard, below)
  keyed(event) {
    if (event.key === "Escape" && this.menuOpen) return this.closeMenu()

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
      case "launcher":
        this.launch()
        break
    }
  }

  // The command palette of this page: what it opens becomes a tile (visiting, below)
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
    this.open(address.href)
    this.closeMenu()
    // A form on this page led here (Turbo follows its redirect right after it ends): a
    // tool was made or renamed, and the menu and the launcher still have the old
    // list. The page is drawn again around the tiles.
    if (performance.now() - this.submittedAt < 1000) Turbo.visit(location.href, { action: "replace" })
  }

  // The server drew this page again (a morph, which leaves the tiles alone): the bar
  // is ours to fill, and a tile whose tool is no longer in the menu has lost it
  refreshed() {
    const tools = new Set(Array.from(document.querySelectorAll("[data-sidebar-tool-link]")).map((link) => toolIdOf(link.getAttribute("href"))))
    for (const [ id, tile ] of Object.entries(this.state.tiles)) {
      if (tools.size > 0 && !tools.has(toolIdOf(tile.url))) this.drop(id)
    }
    this.drawBar()
  }

  // The sidebar is the menu here: in over the tiles, with the keyboard on its first
  // tool, and out again with the keyboard back in the tile
  get menu() {
    return document.querySelector("[data-mobile-sidebar-target='sidebar']")
  }

  get menuOpen() {
    return this.menu?.classList.contains("open")
  }

  toggleMenu() {
    if (this.menuOpen) return this.closeMenu()

    window.focus()
    this.menuTarget.click()
    this.menu?.querySelector("[data-sidebar-tool-link]")?.focus()
  }

  closeMenu() {
    if (!this.menuOpen) return

    const around = this.element.closest("[data-controller~='mobile-sidebar']")
    this.application.getControllerForElementAndIdentifier(around, "mobile-sidebar")?.close()
    this.grabFocus()
  }

  // ── What the pages in the tiles say (side_pane_page_controller.js) ──

  heard(event) {
    if (event.origin !== location.origin) return

    const id = Array.from(this.elements.keys()).find((tile) => this.frameOf(tile)?.contentWindow === event.source)
    const message = event.data || {}
    if (!id || !message.sidePane) return

    switch (message.sidePane) {
      case "location": {
        const path = pathOf(message.url)
        // Sent away from its tool (deleted, or not yours any more): nothing to keep
        if (!toolIdOf(path)) return this.drop(id)

        Object.assign(this.state.tiles[id], { url: path, title: titleOf(message.title, this.appNameValue) })
        this.frameOf(id).title = this.state.tiles[id].title || "Tool"
        this.save()
        this.drawBar()
        break
      }
      case "focus":
        this.focus(id)
        break
      case "command":
        this.run(message.command)
        break
      case "launcher":
        this.launch()
        break
      case "notifications":
        window.focus()
        this.element.querySelector("[data-notifications-target='trigger']")?.click()
        break
      case "leave":
        this.goToNext()
        break
      case "gone":
        this.drop(id)
        break
    }
  }

  // F6 in a tile: on to the next one
  goToNext() {
    const tiles = leaves(this.desk.tree)
    const next = tiles[(tiles.indexOf(this.desk.focus) + 1) % tiles.length]
    if (next) this.focus(next)
    this.grabFocus()
  }

  tellAll(what, details = {}) {
    for (const id of this.elements.keys()) {
      this.frameOf(id)?.contentWindow.postMessage({ sidePane: what, ...details }, location.origin)
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
      for (const [ number, desk ] of Object.entries(kept.desks)) {
        if (!/^[1-9]$/.test(number)) continue

        const tree = pruned(desk?.tree, tiles)
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

// A stored tree with only tiles that still exist; a split that lost a half is the other half
function pruned(node, tiles) {
  if (!node) return null
  if (node.tile) return tiles[node.tile] ? { tile: node.tile } : null

  const first = pruned(node.first, tiles)
  const second = pruned(node.second, tiles)
  if (!first || !second) return first || second

  const ratio = Math.min(0.9, Math.max(0.1, Number(node.ratio) || 0.5))
  return { split: node.split === "column" ? "column" : "row", ratio, first, second }
}

function px(rect) {
  return { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px` }
}

// "Team Chat" from "Team Chat - Dobase"
function titleOf(title, appName) {
  const suffix = ` - ${appName}`
  return title?.endsWith(suffix) ? title.slice(0, -suffix.length) : title || ""
}
