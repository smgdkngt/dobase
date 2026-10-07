import { Controller } from "@hotwired/stimulus"
import { eventToHotkeyString } from "@github/hotkey"
import { typing } from "services/typing"
import { showFlash } from "services/flash"

// On a tool's page that is a tile in the workspace's own page (layouts/tile_frame,
// workspace_controller.js#inThisPage). What tile_page_controller.js does for a tile
// that is a document of its own, as far as a part of a page needs it: it says where
// the page is and what it is called, that the keyboard or a click got here, and
// when Escape has nothing left to let go of.
//
// What a document has to itself, a tile shares with the others on the page:
// - the page's shortcuts (data-hotkey) only work while the keyboard is in this tile;
// - its entries for the shortcuts dialog and the launcher are put there while it is
//   the tile you are in;
// - a link that would put its address in the window's (data-turbo-action) doesn't.
export default class extends Controller {
  static targets = [ "shortcuts", "actions", "flash" ]
  static values = { title: String }

  connect() {
    this.frame = this.element.closest(".tile-frame")
    this.listening = new AbortController()
    const options = { signal: this.listening.signal }
    this.element.addEventListener("focusin", () => this.arrived(false), options)
    this.element.addEventListener("pointerdown", () => this.arrived(true), { ...options, capture: true })
    // (on the document: a key pressed while the keyboard was nowhere is this tile's
    // too, once the workspace has put the keyboard back in it)
    document.addEventListener("keydown", (event) => this.keyed(event), options)
    this.element.addEventListener("click", (event) => event.target.closest?.("[data-turbo-action]")?.removeAttribute("data-turbo-action"), { ...options, capture: true })
    this.report()
    if (this.frame.closest("[data-focused]")) this.offer()
  }

  disconnect() {
    this.listening.abort()
    this.withdraw()
  }

  titleValueChanged() {
    if (this.frame) this.report()
  }

  // What the page has to tell after a form (a notice, what went wrong) is shown the
  // way the page around the tiles shows its own
  flashTargetConnected(message) {
    showFlash(message.content.textContent.trim(), message.dataset.kind === "notice" ? "notice" : "alert")
    message.remove()
  }

  report() {
    this.say("location", { url: this.frame.getAttribute("src"), title: this.titleValue })
  }

  arrived(pointer) {
    this.say("focus", { pointer })
    this.offer()
  }

  // This tile's entries in the shortcuts dialog and the launcher of the page around
  // it, in place of those of the tile that was there before
  offer() {
    for (const [ holder, entries ] of this.holders) {
      if (holder.dataset.tile === this.frame.id || !entries) continue

      holder.replaceChildren(entries.content.cloneNode(true))
      holder.dataset.tile = this.frame.id
    }
  }

  withdraw() {
    for (const [ holder ] of this.holders) {
      if (holder.dataset.tile !== this.frame.id) continue

      holder.replaceChildren()
      delete holder.dataset.tile
    }
  }

  get holders() {
    return [
      [ document.querySelector("[data-tile-shortcuts]"), this.hasShortcutsTarget && this.shortcutsTarget ],
      [ document.querySelector("[data-tile-actions]"), this.hasActionsTarget && this.actionsTarget ]
    ].filter(([ holder ]) => holder)
  }

  keyed(event) {
    if (!this.element.contains(document.activeElement)) return
    if (event.defaultPrevented || typing(event)) return

    // Escape lets go of one thing at a time. A dialog or a menu closes by itself, and
    // a view that had something to let go of took the key before it got here. Then
    // the keyboard leaves what it is on, and with nothing left it leaves the tool:
    // it is on the tile then (workspace_controller.js)
    if (event.key === "Escape") {
      if (document.querySelector("dialog[open], :popover-open")) return

      event.preventDefault()
      return document.activeElement === this.element ? this.say("escape") : this.element.focus({ preventScroll: true })
    }

    const pressed = eventToHotkeyString(event)
    const shortcut = Array.from(this.element.querySelectorAll("[data-hotkey]")).find((element) => element.dataset.hotkey.split(",").includes(pressed))
    if (!shortcut) return

    event.preventDefault()
    shortcut.click()
  }

  say(what, details = {}) {
    this.element.dispatchEvent(new CustomEvent("tile:message", { bubbles: true, detail: { tile: what, ...details } }))
  }
}
