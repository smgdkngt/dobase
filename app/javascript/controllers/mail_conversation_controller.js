import { Controller } from "@hotwired/stimulus"
import { drawnScale, onWholePixel } from "services/tile"

const READER_GOES = ["wheel", "touchstart", "pointerdown", "keydown"]

// A conversation opens on its first open message (the first that was unread, else the
// last), with the closed line before it in sight: the rest is above, a scroll back. Only when the
// conversation is first shown: the page drawing itself again keeps this element, so
// it never connects again then, and where the reader is stays theirs.
export default class extends Controller {
  static targets = ["message"]

  // How long the mails in their frames may take to get their height, which they need
  // before there is room below to scroll to the first open one
  static settling = 3000

  connect() {
    const first = this.messageTargets.find((message) => message.dataset.collapseOpenValue === "true")
    if (!first || this.messageTargets.indexOf(first) < 2) return

    this._scroller = this._findScroller()
    if (!this._scroller) return

    // With the closed line before it in sight, which says there is more above
    this._top = this.messageTargets[this.messageTargets.indexOf(first) - 1]
    this._scroll = this._scroll.bind(this)
    this._stop = this._stop.bind(this)
    this._scrolled = this._scrolled.bind(this)
    this._scroll()

    // Again as the mails get their height, until the reader goes somewhere themselves
    // (a wheel over a mail's frame is heard in the frame only: that shows as a scroll)
    this._observer = new ResizeObserver(this._scroll)
    this.messageTargets.forEach((message) => this._observer?.observe(message))
    READER_GOES.forEach((type) => this.element.addEventListener(type, this._stop, { passive: true }))
    this._scroller.addEventListener("scroll", this._scrolled, { passive: true })
    this._timer = setTimeout(this._stop, /** @type {any} */ (this.constructor).settling)
  }

  disconnect() {
    if (this._top) this._stop()
  }

  _scroll() {
    const scroller = this._scroller
    if (!this._top.isConnected) return this._stop()

    // Measured as drawn, scrolled as laid out: a tile is drawn smaller (services/tile.js)
    const drawn = this._top.getBoundingClientRect().top - scroller.getBoundingClientRect().top - scroller.clientTop
    scroller.scrollTop = onWholePixel(scroller.scrollTop + drawn / drawnScale(scroller), scroller)
    this._at = scroller.scrollTop
  }

  _scrolled() {
    if (Math.abs(this._scroller.scrollTop - this._at) > 1) this._stop()
  }

  _stop() {
    this._observer?.disconnect()
    this._observer = null
    clearTimeout(this._timer)
    READER_GOES.forEach((type) => this.element.removeEventListener(type, this._stop))
    this._scroller.removeEventListener("scroll", this._scrolled)
  }

  // The conversation, or what it lies in where that scrolls instead
  _findScroller() {
    for (let element = this.element; element; element = element.parentElement) {
      if (/auto|scroll/.test(getComputedStyle(element).overflowY)) return element
    }
    return null
  }
}
