import { Controller } from "@hotwired/stimulus"

// Handles context menu display and positioning
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    document.addEventListener("click", this.#closeOnClickOutside.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.#closeOnClickOutside.bind(this))
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

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    this.menuTarget.classList.remove("block")
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

  delete() {
    this.close()
    this.dispatch("action", { detail: { action: "delete", item: this.currentItem } })
  }

  // Private

  #positionAt(x, y) {
    if (!this.hasMenuTarget) return

    const menu = this.menuTarget
    menu.style.left = "0"
    menu.style.top = "0"
    menu.classList.remove("hidden")
    menu.classList.add("block")

    const rect = menu.getBoundingClientRect()
    if (x + rect.width > window.innerWidth) x = window.innerWidth - rect.width - 10
    if (y + rect.height > window.innerHeight) y = window.innerHeight - rect.height - 10

    menu.style.left = `${x}px`
    menu.style.top = `${y}px`
  }

  #closeOnClickOutside(event) {
    if (this.hasMenuTarget && !this.menuTarget.contains(event.target)) {
      this.close()
    }
  }
}
