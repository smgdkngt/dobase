import { Controller } from "@hotwired/stimulus"
import { play } from "services/sound"

// On a message that is being sent. It's brought into view, at the end of a long
// conversation, and the page is refreshed until the mail server has taken it or it's a
// draft again. The refresh morphs the page, and takes this along.
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 } }

  connect() {
    // Its text is in a frame that gets its height a moment after the page shows
    this.settling = new ResizeObserver(() => this.element.scrollIntoView({ block: "start" }))
    this.settling.observe(this.element)
    this.settled = setTimeout(() => this.settling.disconnect(), 1000)
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    this.settling.disconnect()
    clearTimeout(this.settled)
    clearInterval(this.timer)
    // Still on the page, and no longer being sent: the mail server has taken it. (A
    // mail that was refused is a draft again and gone from here; so is a page that was left.)
    if (this.element.isConnected) play("sent", { once: `sent-${this.element.id || location.pathname}` })
  }

  refresh() {
    if (!document.hidden) Turbo.visit(location.href, { action: "replace" })
  }
}
