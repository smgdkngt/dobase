import { Controller } from "@hotwired/stimulus"

// Handles dragging files/folders between folders
export default class extends Controller {
  static targets = ["item", "dropTarget"]
  static values = { toolId: String }

  connect() {
    this.lastClickTime = 0
  }

  dragStart(event) {
    // Prevent drag if this is likely a double-click
    if (Date.now() - this.lastClickTime < 300) {
      event.preventDefault()
      return
    }

    const item = event.currentTarget
    let selected = this.#getSelectedItems()

    // If dragged item isn't selected, drag just that item
    if (!this.#isSelected(item)) {
      const type = item.dataset.itemType
      const id = item.dataset.itemId
      selected = {
        files: type === "file" ? [id] : [],
        folders: type === "folder" ? [id] : []
      }
      // Mark it visually as being dragged
      item.classList.add("opacity-50")
    }

    event.dataTransfer.setData("application/json", JSON.stringify(selected))
    event.dataTransfer.effectAllowed = "move"

    setTimeout(() => {
      this.itemTargets.forEach(i => {
        if (this.#isSelected(i)) i.classList.add("opacity-50")
      })
    }, 0)
  }

  dragEnd() {
    this.itemTargets.forEach(i => i.classList.remove("opacity-50"))
    this.dropTargetTargets.forEach(t => this.#unhighlightDrop(t))
  }

  dragOverFolder(event) {
    if (!event.dataTransfer.types.includes("application/json")) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnterFolder(event) {
    if (!event.dataTransfer.types.includes("application/json")) return
    event.preventDefault()
    const folder = event.currentTarget
    if (folder.classList.contains("opacity-50")) return
    this.#highlightDrop(folder)
  }

  dragLeaveFolder(event) {
    const folder = event.currentTarget
    if (!folder.contains(event.relatedTarget)) {
      this.#unhighlightDrop(folder)
    }
  }

  async dropOnFolder(event) {
    if (!event.dataTransfer.types.includes("application/json")) return
    event.preventDefault()

    const folder = event.currentTarget
    this.#unhighlightDrop(folder)
    if (folder.classList.contains("opacity-50")) return

    const folderId = folder.dataset.itemId
    const data = event.dataTransfer.getData("application/json")
    if (!data) return

    const { files, folders } = JSON.parse(data)
    await this.#moveItems(files, folders, folderId)
  }

  recordClick() {
    this.lastClickTime = Date.now()
  }

  selectionChanged() {
    // Selection state is read from CSS classes, no action needed
  }

  // Private

  #getSelectedItems() {
    // Get from selection controller via data attribute or dispatch
    const files = [], folders = []
    this.itemTargets.forEach(item => {
      if (this.#isSelected(item)) {
        const type = item.dataset.itemType
        const id = item.dataset.itemId
        if (type === "file") files.push(id)
        else if (type === "folder") folders.push(id)
      }
    })
    return { files, folders }
  }

  #isSelected(item) {
    return item.classList.contains("ring-accent")
  }

  #highlightDrop(el) {
    el.classList.add("drop-highlight")
  }

  #unhighlightDrop(el) {
    el.classList.remove("drop-highlight")
  }

  async #moveItems(files, folders, targetFolderId) {
    const promises = []
    // Convert empty string to null for root folder
    const folderId = targetFolderId === "" ? null : targetFolderId

    files.forEach(id => {
      promises.push(fetch(`/tools/${this.toolIdValue}/files/items/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrfToken, "Accept": "application/json" },
        body: JSON.stringify({ file: { folder_id: folderId } })
      }))
    })

    folders.forEach(id => {
      if (id === targetFolderId) return
      promises.push(fetch(`/tools/${this.toolIdValue}/files/folders/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrfToken, "Accept": "application/json" },
        body: JSON.stringify({ folder: { parent_id: folderId } })
      }))
    })

    await Promise.all(promises)
    Turbo.visit(window.location.href, { action: "replace" })
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
