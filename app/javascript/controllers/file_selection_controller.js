import { Controller } from "@hotwired/stimulus"

// Handles file/folder selection (single, multi, shift-select)
export default class extends Controller {
  static targets = ["item", "bulkToolbar", "bulkCount"]

  connect() {
    this.selectedItems = new Set()
    this.lastSelectedIndex = null
    this.lastClickTime = 0
  }

  select(event) {
    event.stopPropagation()

    const item = event.currentTarget.closest("[data-file-selection-target='item']")
    if (!item) return

    this.lastClickTime = Date.now()
    const index = this.itemTargets.indexOf(item)
    const itemId = this.#getItemId(item)

    if (event.shiftKey && this.lastSelectedIndex !== null) {
      this.#rangeSelect(index, event)
    } else if (event.metaKey || event.ctrlKey) {
      this.#toggleSelect(item, itemId)
    } else {
      this.#singleSelect(item, itemId)
    }

    this.lastSelectedIndex = index
    this.#updateToolbar()
    this.dispatch("changed", { detail: { selected: this.selectedItems } })
  }

  clear() {
    this.selectedItems.clear()
    this.itemTargets.forEach(item => this.#deselect(item))
    this.#updateToolbar()
    this.dispatch("changed", { detail: { selected: this.selectedItems } })
  }

  selectAll(event) {
    event?.preventDefault()
    this.itemTargets.forEach(item => {
      this.selectedItems.add(this.#getItemId(item))
      this.#highlight(item)
    })
    this.#updateToolbar()
    this.dispatch("changed", { detail: { selected: this.selectedItems } })
  }

  deselectOutside(event) {
    if (!event.target.closest("[data-file-selection-target='item']")) {
      this.clear()
    }
  }

  getSelected() {
    const files = [], folders = []
    this.selectedItems.forEach(id => {
      const [type, itemId] = id.split("-")
      if (type === "file") files.push(itemId)
      else if (type === "folder") folders.push(itemId)
    })
    return { files, folders }
  }

  // Private

  #rangeSelect(index, event) {
    event.preventDefault()
    const start = Math.min(this.lastSelectedIndex, index)
    const end = Math.max(this.lastSelectedIndex, index)

    if (!event.metaKey && !event.ctrlKey) this.clear()

    for (let i = start; i <= end; i++) {
      const id = this.#getItemId(this.itemTargets[i])
      this.selectedItems.add(id)
      this.#highlight(this.itemTargets[i])
    }
  }

  #toggleSelect(item, itemId) {
    if (this.selectedItems.has(itemId)) {
      this.selectedItems.delete(itemId)
      this.#deselect(item)
    } else {
      this.selectedItems.add(itemId)
      this.#highlight(item)
    }
  }

  #singleSelect(item, itemId) {
    if (!this.selectedItems.has(itemId)) {
      this.clear()
      this.selectedItems.add(itemId)
      this.#highlight(item)
    }
  }

  #highlight(item) {
    item.classList.add("!bg-accent-light", "ring-2", "ring-accent")
  }

  #deselect(item) {
    item.classList.remove("!bg-accent-light", "ring-2", "ring-accent")
  }

  #getItemId(item) {
    return `${item.dataset.itemType}-${item.dataset.itemId}`
  }

  #updateToolbar() {
    if (!this.hasBulkToolbarTarget) return

    if (this.selectedItems.size > 0) {
      this.bulkToolbarTarget.classList.remove("hidden")
      this.bulkToolbarTarget.classList.add("flex")
      this.bulkCountTarget.textContent = `${this.selectedItems.size} selected`
    } else {
      this.bulkToolbarTarget.classList.add("hidden")
      this.bulkToolbarTarget.classList.remove("flex")
    }
  }
}
