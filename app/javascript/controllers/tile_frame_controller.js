import { Controller } from "@hotwired/stimulus"
import { eventToHotkeyString } from "@github/hotkey"
import { typing } from "services/typing"

// On a tool's page that is a tile in the workspace's own page (layouts/tile_frame; a
// trial, see workspace_controller.js#inThisPage). What tile_page_controller.js does
// for a tile that is a document of its own, as far as a part of a page needs it:
// it says where the page is and what it is called, that the keyboard or a click
// got here, and when Escape has nothing left to let go of. The page's shortcuts
// (data-hotkey) only work while the keyboard is in this tile: on a page with
// several tiles a key is the tile's you are in, not the page's.
export default class extends Controller {
  static values = { title: String }

  connect() {
    this.frame = this.element.closest("turbo-frame")
    this.listening = new AbortController()
    const options = { signal: this.listening.signal }
    this.element.addEventListener("focusin", () => this.say("focus", { pointer: false }), options)
    this.element.addEventListener("pointerdown", () => this.say("focus", { pointer: true }), { ...options, capture: true })
    this.element.addEventListener("keydown", (event) => this.keyed(event), options)
    this.report()
  }

  disconnect() {
    this.listening.abort()
  }

  titleValueChanged() {
    if (this.frame) this.report()
  }

  report() {
    this.say("location", { url: this.frame.getAttribute("src"), title: this.titleValue })
  }

  keyed(event) {
    if (event.defaultPrevented || typing(event)) return

    if (event.key === "Escape") {
      if (document.querySelector("dialog[open], :popover-open")) return

      event.preventDefault()
      return this.say("escape")
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
