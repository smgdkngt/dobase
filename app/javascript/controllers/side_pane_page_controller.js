import { Controller } from "@hotwired/stimulus"
import { applyTheme } from "services/theme"

// On a page that is shown beside another one (side_pane_controller.js is on the
// page around it). Says where this page is, so it is the one that comes back after
// a reload, and hands over what only the page around it has: the notifications.
export default class extends Controller {
  connect() {
    this._onMessage = (event) => this.heard(event)
    this._onLoad = () => this.report()
    window.addEventListener("message", this._onMessage)
    // Once the visit is done as well: a page that was redirected to still has the
    // address that was asked for while it is being drawn
    document.addEventListener("turbo:load", this._onLoad)
    this.report()
  }

  disconnect() {
    window.removeEventListener("message", this._onMessage)
    document.removeEventListener("turbo:load", this._onLoad)
  }

  report() {
    this.say("location", { url: location.pathname + location.search, title: document.title })
  }

  heard(event) {
    if (event.origin !== location.origin || event.source !== window.parent) return

    // A theme picked while this page is open; only the page around it hears of it
    if (event.data?.sidePane === "theme") applyTheme(event.data.theme)
  }

  notifications() {
    this.say("notifications")
  }

  // Back to the main tool with the keyboard
  leave() {
    this.say("leave")
  }

  say(what, details = {}) {
    window.parent.postMessage({ sidePane: what, ...details }, location.origin)
  }
}
