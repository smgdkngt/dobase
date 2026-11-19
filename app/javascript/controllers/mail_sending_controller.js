import { Controller } from "@hotwired/stimulus"
import { pageAddress, visitPage } from "services/tile"
import { play } from "services/sound"

// On a message that is being sent. It's brought into view, at the end of a long
// conversation, and the page is refreshed until the mail server has taken it or it's a
// draft again. The refresh morphs the page, and takes this along.
//
// A refresh is only asked for when the one before has come back: a conversation that
// takes longer to draw than the interval was asked for again and again, each time
// breaking off the one before, and never drawn (2026-11-19). After a minute it stops;
// the job that sends the mail tells the open mailbox itself (Tool#announce_change).
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 }, giveUpAfter: { type: Number, default: 60000 } }

  connect() {
    // Its text is in a frame that gets its height a moment after the page shows
    this.settling = new ResizeObserver(() => this.element.scrollIntoView({ block: "start" }))
    this.settling.observe(this.element)
    this.settled = setTimeout(() => this.settling.disconnect(), 1000)

    this.startedAt = Date.now()
    this.waiting = false
    this.cameBack = this.cameBack.bind(this)
    document.addEventListener("turbo:before-fetch-response", this.cameBack)
    document.addEventListener("turbo:fetch-request-error", this.cameBack)
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    this.settling.disconnect()
    clearTimeout(this.settled)
    clearInterval(this.timer)
    clearTimeout(this.lost)
    document.removeEventListener("turbo:before-fetch-response", this.cameBack)
    document.removeEventListener("turbo:fetch-request-error", this.cameBack)
    // Still on the page, and no longer being sent: the mail server has taken it. (A
    // mail that was refused is a draft again and gone from here; so is a page that was left.)
    if (this.element.isConnected) play("sent", { once: `sent-${this.element.id || location.pathname}` })
  }

  refresh() {
    if (Date.now() - this.startedAt > this.giveUpAfterValue) return clearInterval(this.timer)
    if (this.waiting || document.hidden) return

    this.waiting = true
    this.address = pageAddress(this.element).pathname
    // An answer that never comes (a request Turbo dropped for another) doesn't stop it
    this.lost = setTimeout(() => { this.waiting = false }, this.intervalValue * 10)
    visitPage(this.element)
  }

  cameBack(event) {
    const response = event.detail?.fetchResponse?.response
    const url = response?.url || event.detail?.request?.url
    if (!this.waiting || !url || new URL(url, window.location.origin).pathname !== this.address) return

    this.waiting = false
    clearTimeout(this.lost)
  }
}
