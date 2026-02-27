import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["to", "bccField", "fileInput", "attachmentsList", "attachmentsArea"]

  connect() {
    this.files = []
  }

  toggleBcc(event) {
    event.preventDefault()
    if (this.hasBccFieldTarget) {
      this.bccFieldTarget.classList.toggle("hidden")
      if (!this.bccFieldTarget.classList.contains("hidden")) {
        this.bccFieldTarget.querySelector("input")?.focus()
      }
    }
  }

  handleFiles(event) {
    const newFiles = Array.from(event.target.files)
    this.files.push(...newFiles)
    this.renderAttachments()
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.files.splice(index, 1)
    this.renderAttachments()
    this.updateFileInput()
  }

  renderAttachments() {
    if (!this.hasAttachmentsListTarget) return

    this.attachmentsListTarget.innerHTML = this.files.map((file, index) => `
      <div class="compose-attachment-item">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path>
          <polyline points="13 2 13 9 20 9"></polyline>
        </svg>
        <span>${this.truncateName(file.name, 20)}</span>
        <span class="compose-attachment-size">${this.formatSize(file.size)}</span>
        <button type="button" class="compose-attachment-remove" data-index="${index}" data-action="click->compose#removeFile">×</button>
      </div>
    `).join("")
  }

  updateFileInput() {
    const dt = new DataTransfer()
    this.files.forEach(file => dt.items.add(file))
    if (this.hasFileInputTarget) {
      this.fileInputTarget.files = dt.files
    }
  }

  truncateName(str, length) {
    if (str.length <= length) return str
    const parts = str.split(".")
    const ext = parts.length > 1 ? parts.pop() : ""
    const name = parts.join(".")
    if (ext) {
      const truncatedName = name.slice(0, length - ext.length - 4) + "..."
      return truncatedName + "." + ext
    }
    return str.slice(0, length - 3) + "..."
  }

  formatSize(bytes) {
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
    return (bytes / (1024 * 1024)).toFixed(1) + " MB"
  }
}
