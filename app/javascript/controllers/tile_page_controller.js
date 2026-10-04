import { Controller } from "@hotwired/stimulus"
import { applyTheme } from "services/theme"
import { workspaceCommand, isLauncherKey, renameWorkspaceKeys } from "services/workspace_keys"
import { opensAsTile } from "services/tool_frame"
import { typing } from "services/typing"
import { floating, floatedAt } from "services/float"

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
    // Backspace outside a field is "back" to some browsers (Vivaldi, Firefox by a
    // setting). With several tiles the browser's history is all of theirs in one line,
    // so that goes back in whichever tile went somewhere last: another tool changes
    // under a key meant for this one. Here it is nobody's key unless a view took it
    // (a chat message deletes on it), which they have by the time it gets to the window.
    this._onBackspace = (event) => { if (event.key === "Backspace" && !typing(event)) event.preventDefault() }
    window.addEventListener("keydown", this._onBackspace)
    // Escape lets go of things one at a time: a dialog or a menu closes, a view lets go
    // of what is picked (they take the key, and it doesn't count here), then the
    // keyboard leaves what it is on. With nothing left to let go of it leaves the tool:
    // the keyboard is on the tile then, where the arrows go from tile to tile
    // (workspace_controller.js).
    this._onEscape = (event) => {
      if (event.key !== "Escape" || event.defaultPrevented || typing(event)) return
      if (document.querySelector("dialog[open], :popover-open, [aria-modal='true']:not([hidden]):not(dialog)")) return

      event.preventDefault()
      const on = document.activeElement
      if (on && on !== document.body && on !== document.documentElement) return on.blur()

      this.say("escape")
    }
    window.addEventListener("keydown", this._onEscape)
    // Chosen in this page's own shortcuts dialog: the workspace and the other tiles hear of it
    this._onKeysChosen = (event) => this.say("keys", { chosen: event.detail })
    window.addEventListener("workspace:keys-chosen", this._onKeysChosen)
    // A theme picked while this page is open: the workspace says so here, and the
    // tile wears it in the same moment (workspace_controller.js#wearAll)
    this._onTheme = (event) => applyTheme(event.detail, { fade: false })
    window.addEventListener("workspace:theme", this._onTheme)
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
    if (floating) this.float()
  }

  // This page floats over the workspace to show one dialog (services/float.js). When
  // that dialog is closed, or the page went somewhere that has none (the card was
  // deleted, a link in it was followed), the workspace takes the frame away. A dialog
  // takes a moment to open after the page arrives, and to be gone after it closes.
  float() {
    const gone = () => {
      if (!document.querySelector("dialog[open]")) this.say("float-closed", { url: location.pathname + location.search })
    }
    this._onDialogClosed = () => setTimeout(gone, 0)
    // (at the address that opens the dialog it is on its way; anywhere else there is none to wait for)
    this._onFloatLoad = () => {
      clearTimeout(this._floatCheck)
      this._floatCheck = setTimeout(gone, location.pathname + location.search === floatedAt ? 1500 : 50)
    }
    document.addEventListener("close", this._onDialogClosed, true)
    document.addEventListener("turbo:load", this._onFloatLoad)
    this._onFloatLoad()
  }

  disconnect() {
    window.removeEventListener("message", this._onMessage)
    window.removeEventListener("workspace:theme", this._onTheme)
    window.removeEventListener("keydown", this._onBackspace)
    window.removeEventListener("keydown", this._onEscape)
    window.removeEventListener("workspace:keys-chosen", this._onKeysChosen)
    window.removeEventListener("focus", this._onFocus)
    document.removeEventListener("pointerdown", this._onFocus, true)
    document.removeEventListener("click", this._onClick, true)
    document.removeEventListener("turbo:load", this._onLoad)
    document.removeEventListener("keydown", this._onKey, true)
    document.removeEventListener("close", this._onDialogClosed, true)
    document.removeEventListener("turbo:load", this._onFloatLoad)
    clearTimeout(this._floatCheck)
  }

  report() {
    this.say("location", { url: location.pathname + location.search, title: document.title })
  }

  heard(event) {
    if (event.origin !== location.origin || event.source !== window.parent) return

    // (the theme once more, for a page that was still loading when it was said)
    if (event.data?.tile === "theme") applyTheme(event.data.theme, { fade: false })
    // The workspace's keys go with another modifier: this page names them too
    if (event.data?.tile === "keys") renameWorkspaceKeys(event.data.chosen || {})
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
