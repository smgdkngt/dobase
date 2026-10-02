import { Controller } from "@hotwired/stimulus"
import { typing } from "services/typing"

// Keyboard shortcuts are handled declaratively via data-hotkey attributes
// in the view. This controller only provides the behavior methods that
// those hotkey-triggered buttons call.

export default class extends Controller {
  static targets = ["list", "item", "reader"]

  connect() {
    this._onFrameLoad = this._handleFrameLoad.bind(this)
    const frame = document.getElementById("mail-content")
    if (frame) frame.addEventListener("turbo:frame-load", this._onFrameLoad)
    this._onKey = (event) => this._keyed(event)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    const frame = document.getElementById("mail-content")
    if (frame) frame.removeEventListener("turbo:frame-load", this._onFrameLoad)
    document.removeEventListener("keydown", this._onKey)
  }

  // The arrow keys are listened for here, not through hidden hotkey buttons as the
  // letters are: a hotkey takes its key whatever else is going on, and the arrows are
  // also how you scroll a dialog that lies over the mail.
  _keyed(event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (typing(event) || document.querySelector("dialog[open], :popover-open")) return

    const act = {
      ArrowDown: () => this._arrow(1, event),
      ArrowUp: () => this._arrow(-1, event),
      ArrowRight: () => this._in(event),
      ArrowLeft: () => this._out(event),
      Home: () => this._far(-1),
      End: () => this._far(1),
      PageDown: () => this._page(1),
      PageUp: () => this._page(-1),
      " ": () => this._page(event.shiftKey ? -1 : 1)
    }[event.key]
    // With Shift the arrows select text; the space bar is a button's when it is on one
    if (!act || (event.shiftKey && event.key !== " ")) return
    if (event.key === " " && event.target.matches?.("a[href], button, input, summary, [role='button']")) return

    event.preventDefault()
    act()
  }

  get items() {
    return this.hasListTarget
      ? [...this.listTarget.querySelectorAll("[data-mail-keyboard-target='item']")]
      : this.itemTargets
  }

  get selectedItem() {
    return this.items.find(item => item.classList.contains("selected"))
  }

  get selectedIndex() {
    return this.selectedItem ? this.items.indexOf(this.selectedItem) : -1
  }

  selectNext() {
    const items = this.items
    if (!items.length) return
    const next = (this.selectedIndex + 1) % items.length
    this.navigateToItem(items[next])
  }

  selectPrevious() {
    const items = this.items
    if (!items.length) return
    const prev = this.selectedIndex > 0 ? this.selectedIndex - 1 : items.length - 1
    this.navigateToItem(items[prev])
  }

  // The arrow keys
  //
  // In the list they go from conversation to conversation: with the message beside
  // the list each one opens as you get to it, as j and k do; in a narrow window (a
  // tile in the workspace, a phone with a keyboard) they move a highlight, and Enter
  // or the right arrow opens. The right arrow goes into the message: there up and
  // down read on, the space bar turns the page, Home and End go to its top and its
  // end, and the left arrow comes back to the list. Past the list or the message on
  // a side, the arrows say "edge", as arrow_keys_controller.js does for the other
  // tools: in the workspace the tile on that side takes over.
  down() {
    this._arrow(1)
  }

  up() {
    this._arrow(-1)
  }

  get reading() {
    return !this._listShows || this.element.hasAttribute("data-reading")
  }

  _arrow(step, event) {
    if (this.reading) return this._readOn(step * 80)

    const items = this.items
    const at = this.selectedIndex
    const to = at < 0 ? (step > 0 ? 0 : items.length - 1) : at + step
    if (!items[to]) return this._edge(step > 0 ? "down" : "up", event)

    this._goTo(items[to])
  }

  // To a conversation: opened where the message shows beside the list, lit where it doesn't
  _goTo(item) {
    if (this._messageShows) return this.navigateToItem(item)

    this.items.forEach((other) => other.classList.remove("selected"))
    item.classList.add("selected")
    item.scrollIntoView({ block: "nearest" })
  }

  _far(step) {
    if (this.reading) return this._scroller?.scrollTo({ top: step > 0 ? this._scroller.scrollHeight : 0 })

    const items = this.items
    if (items.length) this._goTo(step > 0 ? items.at(-1) : items[0])
  }

  _page(step) {
    if (!this._messageShows) return

    const scroller = this._scroller
    scroller?.scrollBy({ top: step * scroller.clientHeight * 0.85 })
  }

  // The right arrow: into the conversation
  _in(event) {
    if (!this._listShows || this.element.hasAttribute("data-reading")) return this._edge("right", event)
    if (!this._messageShows) return this.selectedItem ? this.openSelected() : this._edge("right", event)
    if (!this.selectedItem || !this._scroller) return this._edge("right", event)

    this.element.setAttribute("data-reading", "")
  }

  // The left arrow: back to the list
  _out(event) {
    if (!this._listShows) return this.backToList()
    if (!this.element.hasAttribute("data-reading")) return this._edge("left", event)

    this.element.removeAttribute("data-reading")
  }

  _readOn(by) {
    this._scroller?.scrollBy({ top: by })
  }

  // What scrolls the message that shows: the reader, or what it lies in
  get _scroller() {
    const reader = this.readerTargets.find((target) => target.getClientRects().length > 0)
    for (let element = reader; element && element !== this.element.parentElement; element = element.parentElement) {
      if (element.scrollHeight > element.clientHeight + 1 && /auto|scroll/.test(getComputedStyle(element).overflowY)) return element
    }
    return reader || null
  }

  // Nothing further on that side (arrow_keys_controller.js says it the same way)
  _edge(side, event) {
    const page = this.element.closest("main") || this.element
    page.dispatchEvent(new CustomEvent("arrow-keys:edge", { bubbles: true, cancelable: true, detail: { side, repeat: Boolean(event?.repeat) } }))
  }

  // Only where the list and the message take turns: side by side there is nothing to go back to
  backToList() {
    if (this._listShows) return

    this.element.classList.remove("mail-detail-open")
  }

  get _listShows() {
    return this.hasListTarget && this.listTarget.getClientRects().length > 0
  }

  get _messageShows() {
    const frame = document.getElementById("mail-content")
    return Boolean(frame) && frame.getClientRects().length > 0
  }

  navigateToItem(item) {
    if (!item) return
    // Update visual selection immediately
    this.items.forEach(i => i.classList.remove("selected"))
    item.classList.add("selected")
    // The global prefers-reduced-motion rule can't reach a behavior passed in
    // JavaScript, so ask for the preference here instead.
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    item.scrollIntoView({ block: "nearest", behavior: reduceMotion ? "auto" : "smooth" })

    // Mark as read visually (the server marks it read, but the list doesn't re-render)
    this._markItemRead(item)

    const link = item.querySelector("a[href]")
    if (link) link.click()
  }

  selectItem(event) {
    const item = event.currentTarget.closest("[data-mail-keyboard-target='item']")
    if (!item) return
    this.element.removeAttribute("data-reading")
    this.items.forEach(i => i.classList.remove("selected"))
    item.classList.add("selected")
    this._markItemRead(item)
  }

  openSelected() {
    const selected = this.selectedItem
    if (!selected) return
    const link = selected.querySelector("a[href]")
    if (link) link.click()
  }

  deselect() {
    this.element.removeAttribute("data-reading")
    this.items.forEach(item => item.classList.remove("selected"))
    document.activeElement?.blur()
  }

  // Toggle mobile detail view when mail-content frame loads
  _handleFrameLoad() {
    this.element.classList.add("mail-detail-open")
  }

  // Remove unread indicators from a conversation item (dot, bold from/subject)
  _markItemRead(item) {
    const dot = item.querySelector(".bg-accent.rounded-full.w-2.h-2")
    if (dot) dot.remove()

    item.querySelectorAll(".font-semibold, .font-medium").forEach(el => {
      el.classList.remove("font-semibold", "font-medium")
    })
  }
}
