import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["to", "bccField", "fileInput", "attachmentsList"]

  connect() {
    this.files = []
    this._submitting = false
    this._savedDraft = !!this.element.querySelector("input[name='draft_id']")
    this._snapshot = this._formSnapshot()
    this._beforeUnload = (e) => {
      if (this._hasContent() && !this._submitting) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    this._beforeVisit = (e) => {
      if (this._hasContent() && !this._submitting) {
        if (!confirm("You have an unsent message. Discard it?")) {
          e.preventDefault()
        }
      }
    }
    window.addEventListener("beforeunload", this._beforeUnload)
    document.addEventListener("turbo:before-visit", this._beforeVisit)

    this.element.addEventListener("submit", () => { this._submitting = true })
  }

  disconnect() {
    window.removeEventListener("beforeunload", this._beforeUnload)
    document.removeEventListener("turbo:before-visit", this._beforeVisit)
  }

  _hasContent() {
    // Draft saved and no changes since — nothing to lose
    if (this._savedDraft && this._formSnapshot() === this._snapshot) return false

    const form = this.element
    const to = form.querySelector("input[name='to']")?.value?.trim()
    const subject = form.querySelector("input[name='subject']")?.value?.trim()
    const bodyHtml = form.querySelector("input[name='body']")?.value || ""
    const bodyText = bodyHtml.replace(/<[^>]*>/g, "").trim()
    return !!(to || subject || bodyText)
  }

  _formSnapshot() {
    const form = this.element
    const to = form.querySelector("input[name='to']")?.value || ""
    const subject = form.querySelector("input[name='subject']")?.value || ""
    const body = form.querySelector("input[name='body']")?.value || ""
    return `${to}|${subject}|${body}`
  }

  discard() {
    this._submitting = true // skip confirmation
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
