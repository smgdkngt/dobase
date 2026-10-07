import { Controller } from "@hotwired/stimulus"
import { visitPage, openPage } from "services/tile"

// Main coordinator for file manager - delegates to focused controllers
export default class extends Controller {
  static targets = [
    "shareDialog", "folderDialog", "folderNameInput", "renameDialog", "renameInput"
  ]
  static values = { toolId: String }

  // Escape shortcut handled via data-hotkey in the view

  // ── Open item (double-click) ──

  // Tiles open on double-click with a mouse; Enter does it from the keyboard.
  // On a file or a folder: Enter opens it, the space bar picks it (or lets it go)
  // beside whatever else is picked, the way a click with Command or Control does
  openItemKey(event) {
    if (event.target !== event.currentTarget || (event.key !== "Enter" && event.key !== " ")) return
    event.preventDefault()
    if (event.key === "Enter") return this.openItem(event)

    event.currentTarget.dispatchEvent(new MouseEvent("click", { bubbles: true, ctrlKey: true }))
  }

  openItem(event) {
    const item = event.currentTarget.closest("[data-item-url]")
    if (item?.dataset.itemUrl) {
      openPage(this.element, item.dataset.itemUrl)
    }
  }

  // ── Context menu action handlers ──

  handleContextAction(event) {
    const { action, item } = event.detail
    if (!item) return

    switch (action) {
      case "open":
        if (item.dataset.itemUrl) openPage(this.element, item.dataset.itemUrl)
        break
      case "download":
        this.#downloadItem(item)
        break
      case "rename":
        this.#showRenameDialog(item)
        break
      case "share":
        this.#showShareDialog(item)
        break
    }
  }

  // ── Dialogs ──

  newFolder() {
    this.folderDialogTarget.showModal()
    this.folderNameInputTarget.value = ""
    this.folderNameInputTarget.focus()
  }

  closeFolderDialog() {
    this.folderDialogTarget.close()
  }

  closeShareDialog() {
    this.shareDialogTarget.close()
  }

  submitRename(event) {
    event.preventDefault()
    const type = this.renameDialogTarget.dataset.itemType
    const id = this.renameDialogTarget.dataset.itemId
    const name = this.renameInputTarget.value.trim()
    if (!name) return

    const url = type === "folder"
      ? `/tools/${this.toolIdValue}/files/folders/${id}`
      : `/tools/${this.toolIdValue}/files/items/${id}`
    const body = type === "folder"
      ? JSON.stringify({ folder: { name } })
      : JSON.stringify({ file: { name } })

    // (through Turbo: the page knows the change for its own, live_controller.js)
    Turbo.fetch(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrfToken, "Accept": "application/json" },
      body
    }).then(r => r.ok && visitPage(this.element))

    this.renameDialogTarget.close()
  }

  closeRenameDialog() {
    this.renameDialogTarget.close()
  }

  // ── Private ──

  #downloadItem(item) {
    const type = item.dataset.itemType
    const id = item.dataset.itemId
    const url = type === "folder"
      ? `/tools/${this.toolIdValue}/files/folders/${id}/download`
      : `/tools/${this.toolIdValue}/files/items/${id}/download`
    window.location.href = url
  }

  #showRenameDialog(item) {
    const nameEl = item.querySelector("[data-item-name]")
    this.renameInputTarget.value = nameEl?.textContent?.trim() || ""
    this.renameDialogTarget.dataset.itemType = item.dataset.itemType
    this.renameDialogTarget.dataset.itemId = item.dataset.itemId
    this.renameDialogTarget.showModal()
    this.renameInputTarget.select()
  }

  #showShareDialog(item) {
    const type = item.dataset.itemType
    const id = item.dataset.itemId
    const url = type === "folder"
      ? `/tools/${this.toolIdValue}/files/folders/${id}/share`
      : `/tools/${this.toolIdValue}/files/items/${id}/share`
    const frame = this.shareDialogTarget.querySelector("turbo-frame")
    if (frame) frame.src = url
    this.shareDialogTarget.showModal()
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
