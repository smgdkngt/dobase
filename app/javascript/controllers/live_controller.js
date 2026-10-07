import { Controller } from "@hotwired/stimulus"
import { refresher } from "services/live"
import { pageInUse, unsentText } from "services/page_in_use"
import { pageAddress, tileOf, visitPage } from "services/tile"

// A tool's page that shows what changes in the tool while it is open, whoever did it
// and from where: another window, a colleague, the CLI. The server only says that
// something changed (AnnouncesChanges, Tool#announce_change), on the stream the page
// already listens to for who is here (presence_controller.js hands it on as
// presence:changed). The page then asks for itself again and lays the answer over
// what is there (a morph: what is open and how far it is scrolled stay).
//
// When it does that, and when it waits, is services/live.js. Waiting is for whoever
// is at work in the page: nothing is drawn while a dialog or a menu is open, the
// cursor is in a field, a field holds text that wasn't sent, or something is held
// with the pointer.
//
// On <main> of the tools that have it (main_attributes), and so on a tile in the
// workspace's own page too (layouts/tile_frame).
const DRAWING_TAKES_AT_MOST_MS = 10000

export default class extends Controller {
  connect() {
    this.refresher = refresher({ draw: () => this.draw(), busy: () => this.busy })
    this.listening = new AbortController()
    const options = { signal: this.listening.signal }
    const always = { ...options, capture: true }

    this.element.addEventListener("presence:changed", (event) => this.changed(event.detail), options)
    document.addEventListener("visibilitychange", () => this.refresher.look(), options)

    // A pointer that is down is holding something: a card on its way to another
    // column. A drag the browser does itself ends the pointer's events, and one let
    // go of outside the page never says so here: the next move without a button does.
    window.addEventListener("pointerdown", () => { this.held = true }, always)
    window.addEventListener("pointerup", () => { this.held = false }, always)
    window.addEventListener("pointercancel", () => { this.held = false }, always)
    window.addEventListener("pointermove", (event) => { if (event.buttons === 0) this.held = false }, always)
    window.addEventListener("dragstart", () => { this.dragging = true }, always)
    window.addEventListener("dragend", () => { this.dragging = false }, always)
    window.addEventListener("drop", () => { this.dragging = false }, always)

    // The page of a tile in the workspace's own page is that tile's frame
    const tile = tileOf(this.element)
    const page = tile || document
    page.addEventListener("turbo:before-fetch-request", () => { this.asked += 1 }, options)
    page.addEventListener(tile ? "turbo:before-frame-render" : "turbo:before-render", (event) => this.hold(event), options)
  }

  disconnect() {
    this.listening.abort()
    this.refresher.stop()
  }

  changed({ by } = {}) {
    if (this.mine(by)) return

    this.refresher.changed()
  }

  // The page that made a change has drawn it already. Turbo keeps the requests a
  // document sent (services/api.js sends its own through it). Tiles in the
  // workspace's page are one document: there the change is the doing of the tile
  // you are in, and another tile of the same tool draws it.
  mine(by) {
    if (!by || !window.Turbo?.session.recentRequests.has(by)) return false

    const tile = tileOf(this.element)
    return !tile || Boolean(tile.closest("[aria-current='true']"))
  }

  get busy() {
    return document.hidden || this.held || this.dragging || pageInUse() || unsentText(this.element)
  }

  draw() {
    this.address = pageAddress(this.element).href
    this.asked = 0
    this.drawing = performance.now()
    visitPage(this.element)
  }

  // Between asking for the page and getting it, someone can have opened a dialog:
  // drawing would close it under their hands. The page stays as it is then, and
  // behind. Only for the drawing that was asked for here: once anything was asked
  // for besides it (a link, a form), what arrives is that, and is drawn.
  hold(event) {
    const ours = this.drawing && performance.now() - this.drawing < DRAWING_TAKES_AT_MOST_MS &&
      this.asked <= 1 && pageAddress(this.element).href === this.address
    this.drawing = null
    if (!ours || !this.busy) return

    event.detail.render = () => {}
    this.refresher.changed()
  }
}
