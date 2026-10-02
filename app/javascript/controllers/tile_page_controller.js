import { Controller } from "@hotwired/stimulus"
import { applyTheme } from "services/theme"
import { workspaceCommand, isLauncherKey } from "services/workspace_keys"
import { opensAsTile } from "services/tool_frame"

// On a page that is a tile in the workspace (workspace_controller.js is on the page
// around it). Says where this page is, so it is the one that comes back after a
// reload, and hands over what only the page around it has: the notifications, the
// launcher and the keys that move tiles.
export default class extends Controller {
  connect() {
    this._onMessage = (event) => this.heard(event)
    this._onLoad = () => this.report()
    this._onKey = (event) => this.keyed(event)
    this._onFocus = (event) => this.say("focus", { pointer: event.type === "pointerdown" })
    this._onClick = (event) => this.clicked(event)
    document.addEventListener("click", this._onClick, true)
    window.addEventListener("message", this._onMessage)
    // The keyboard arrives here by Tab or F6, or with a click
    window.addEventListener("focus", this._onFocus)
    document.addEventListener("pointerdown", this._onFocus, true)
    // Before the page's own shortcuts get the key
    document.addEventListener("keydown", this._onKey, true)
    // Once the visit is done as well: a page that was redirected to still has the
    // address that was asked for while it is being drawn
    document.addEventListener("turbo:load", this._onLoad)
    this.report()
  }

  disconnect() {
    window.removeEventListener("message", this._onMessage)
    window.removeEventListener("focus", this._onFocus)
    document.removeEventListener("pointerdown", this._onFocus, true)
    document.removeEventListener("click", this._onClick, true)
    document.removeEventListener("turbo:load", this._onLoad)
    document.removeEventListener("keydown", this._onKey, true)
  }

  report() {
    this.say("location", { url: location.pathname + location.search, title: document.title })
  }

  heard(event) {
    if (event.origin !== location.origin || event.source !== window.parent) return

    // A theme picked while this page is open; only the page around it hears of it
    if (event.data?.tile === "theme") applyTheme(event.data.theme)
  }

  notifications() {
    this.say("notifications")
  }

  // Alt and a click on a link to a tool's page opens it as a tile of its own: this
  // document stays, and the other one comes beside it
  clicked(event) {
    if (!event.altKey || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return

    const link = event.target.closest?.("a[href]")
    if (!link || !opensAsTile(link)) return

    event.preventDefault()
    event.stopPropagation()
    this.say("open", { url: link.pathname + link.search + link.hash })
  }

  // Not through the shortcut library: that leaves keys typed in a field alone, and a
  // field is where you usually are.
  keyed(event) {
    // On to the next tile, with Shift back to the one before
    if (event.key === "F6") return this.handOn(event, "next", { back: event.shiftKey })

    // The workspace has one launcher (with Shift it is this page's own palette, which
    // knows what the page can do), and the keys that move tiles are its own
    const command = workspaceCommand(event)
    if (command) return this.handOn(event, "command", { command })
    if (isLauncherKey(event)) this.handOn(event, "launcher")
  }

  handOn(event, what, details) {
    event.preventDefault()
    event.stopPropagation()
    this.say(what, details)
  }

  say(what, details = {}) {
    window.parent.postMessage({ tile: what, ...details }, location.origin)
  }
}
