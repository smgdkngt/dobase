import { Controller } from "@hotwired/stimulus"
import { visitPage } from "services/tile"
import { api } from "services/api"

export default class extends Controller {
  static targets = ["shareDialog", "shareContent", "shareLinkInput"]
  static values = { fileId: String, toolId: String }

  createShare() {
    this.shareDialogTarget.showModal()
  }

  manageShare() {
    this.shareDialogTarget.showModal()
  }

  closeShareDialog() {
    this.shareDialogTarget.close()
  }

  copyShareLink() {
    const input = this.shareLinkInputTarget
    input.select()
    navigator.clipboard.writeText(input.value)

    // Visual feedback
    const btn = this.element.querySelector("[data-action='file-preview#copyShareLink']")
    const originalText = btn.textContent
    btn.textContent = "Copied!"
    setTimeout(() => btn.textContent = originalText, 2000)
  }

  onShareCreated(event) {
    if (event.detail.success) {
      visitPage(this.element)
    }
  }

  async deleteFile() {
    await api(`/tools/${this.toolIdValue}/files/items/${this.fileIdValue}`, "DELETE")
    // Redirect handled by controller
  }
}
