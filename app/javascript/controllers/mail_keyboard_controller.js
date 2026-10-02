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
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
    if (typing(event) || document.querySelector("dialog[open], :popover-open")) return

    const act = {
      ArrowDown: () => this.down(),
      ArrowUp: () => this.up(),
      ArrowRight: () => this.openSelected(),
      ArrowLeft: () => this.backToList()
    }[event.key]
    if (!act) return

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
  // With the list and the message side by side they read on to the next conversation,
  // as j and k do. In a narrow window (a tile in the workspace, a phone with a
  // keyboard) the list and the message take turns: in the list the arrows move a
  // highlight and Enter or the right arrow opens; in the message they scroll, and the
  // left arrow goes back to the list.
  down() {
    this._arrow(1)
  }

  up() {
    this._arrow(-1)
  }

  _arrow(step) {
    if (!this._listShows) return this._readOn(step)
    if (this._messageShows) return step > 0 ? this.selectNext() : this.selectPrevious()

    const items = this.items
    if (!items.length) return

    const next = this.selectedIndex < 0 ? (step > 0 ? 0 : items.length - 1) : Math.min(items.length - 1, Math.max(0, this.selectedIndex + step))
    items.forEach((item) => item.classList.remove("selected"))
    items[next].classList.add("selected")
    items[next].scrollIntoView({ block: "nearest" })
  }

  _readOn(step) {
    const reader = this.readerTargets.find((target) => target.getClientRects().length > 0)
    reader?.scrollBy({ top: step * 80 })
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
