import { Controller } from "@hotwired/stimulus"

// Keyboard shortcuts are handled declaratively via data-hotkey attributes
// in the view. This controller only provides the behavior methods that
// those hotkey-triggered buttons call.

export default class extends Controller {
  static targets = ["list", "item"]

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
    const link = item.querySelector("a[href]")
    if (link) {
      link.click()
    } else {
      this.items.forEach(i => i.classList.remove("selected"))
      item.classList.add("selected")
      item.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
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
}
