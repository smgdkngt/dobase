import { Controller } from "@hotwired/stimulus"

// Keyboard shortcuts are handled declaratively via data-hotkey attributes
// in the view. This controller only provides the behavior methods that
// those hotkey-triggered buttons call.

export default class extends Controller {
  static targets = ["list", "item"]

  connect() {
    this._onFrameLoad = this._handleFrameLoad.bind(this)
    const frame = document.getElementById("mail-content")
    if (frame) frame.addEventListener("turbo:frame-load", this._onFrameLoad)
  }

  disconnect() {
    const frame = document.getElementById("mail-content")
    if (frame) frame.removeEventListener("turbo:frame-load", this._onFrameLoad)
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

  navigateToItem(item) {
    if (!item) return
    // Update visual selection immediately
    this.items.forEach(i => i.classList.remove("selected"))
    item.classList.add("selected")
    item.scrollIntoView({ block: "nearest", behavior: "smooth" })

    // Mark as read visually (the server marks it read, but the list doesn't re-render)
    this._markItemRead(item)

    const link = item.querySelector("a[href]")
    if (link) link.click()
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
