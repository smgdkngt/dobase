import { Controller } from "@hotwired/stimulus"
import { zoomOf } from "services/tile"

// Handles context menu display and positioning
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Keep the bound function: removeEventListener needs the same one, or every
    // visit to the page would leave another document listener behind
    this.closeOnClickOutside = this.#closeOnClickOutside.bind(this)
    document.addEventListener("click", this.closeOnClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside)
  }

  show(event) {
    event.preventDefault()
    event.stopPropagation()

    const item = event.currentTarget.closest("[data-item-id]")
    this.currentItem = item

    this.#positionAt(event.clientX, event.clientY)
    this.dispatch("opened", { detail: { item } })
  }

  showFromButton(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const item = button.closest("[data-item-id]")
    this.currentItem = item

    const rect = button.getBoundingClientRect()
    this.#positionAt(rect.left, rect.bottom + 4)
    this.dispatch("opened", { detail: { item } })
  }

  // Escape closes the menu when it is open, and is then nobody else's
  escape(event) {
    if (!this.hasMenuTarget || this.menuTarget.classList.contains("hidden")) return

    event.preventDefault()
    this.close()
  }

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    this.menuTarget.classList.remove("block")
    this.menuTarget.removeAttribute("data-live-busy")
  }

  // Actions delegate to parent controller via events
  open() {
    this.close()
    this.dispatch("action", { detail: { action: "open", item: this.currentItem } })
  }

  download() {
    this.close()
    this.dispatch("action", { detail: { action: "download", item: this.currentItem } })
  }

  rename() {
    this.close()
    this.dispatch("action", { detail: { action: "rename", item: this.currentItem } })
  }

  share() {
    this.close()
    this.dispatch("action", { detail: { action: "share", item: this.currentItem } })
  }

  // Private

  #positionAt(x, y) {
    if (!this.hasMenuTarget) return

    const menu = this.menuTarget
    menu.style.left = "0"
    menu.style.top = "0"
    menu.classList.remove("hidden")
    menu.classList.add("block")
    // Open by a class the server doesn't know of: the page isn't drawn again under it
    menu.setAttribute("data-live-busy", "")

    const rect = menu.getBoundingClientRect()
    if (x + rect.width > window.innerWidth) x = window.innerWidth - rect.width - 10
    if (y + rect.height > window.innerHeight) y = window.innerHeight - rect.height - 10

    // (where the pointer is on the screen is measured as drawn, where the menu is put
    // as laid out: a tile in the workspace's page is drawn smaller than that)
    const zoom = zoomOf(menu)
    menu.style.left = `${x / zoom}px`
    menu.style.top = `${y / zoom}px`
  }

  #closeOnClickOutside(event) {
    if (this.hasMenuTarget && !this.menuTarget.contains(event.target)) {
      this.close()
    }
  }
}
