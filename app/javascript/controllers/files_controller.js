import { Controller } from "@hotwired/stimulus"

// Main coordinator for file manager - delegates to focused controllers
export default class extends Controller {
  static targets = [
    "shareDialog", "folderDialog", "folderNameInput", "renameDialog", "renameInput"
  ]
  static values = { toolId: String }

  // Escape shortcut handled via data-hotkey in the view

  // ── Open item (double-click) ──

  openItem(event) {
    const item = event.currentTarget.closest("[data-item-url]")
    if (item?.dataset.itemUrl) {
      Turbo.visit(item.dataset.itemUrl)
    }
  }

  // ── Context menu action handlers ──

  handleContextAction(event) {
    const { action, item } = event.detail
    if (!item) return

    switch (action) {
      case "open":
        if (item.dataset.itemUrl) Turbo.visit(item.dataset.itemUrl)
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
      case "delete":
        this.#deleteItems()
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

    fetch(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrfToken, "Accept": "application/json" },
      body
    }).then(r => r.ok && Turbo.visit(window.location.href, { action: "replace" }))

    this.renameDialogTarget.close()
  }

  closeRenameDialog() {
    this.renameDialogTarget.close()
  }

  // ── Bulk actions ──

  bulkDownload() {
    // Delegate to selection controller to get selected items
    this.dispatch("requestDownload")
  }

  bulkDelete() {
    this.#deleteItems()
  }

  bulkCancel() {
    this.dispatch("clearSelection")
  }

  // ── Private ──

  clearSelection() {
    this.dispatch("clearSelection")
  }

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

  async #deleteItems() {
    // This would need coordination with selection controller
    // For now, dispatch an event that the selection controller can handle
    this.dispatch("requestDelete")
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
