import { Controller } from "@hotwired/stimulus"
import { formatFileSize } from "services/file_size"

const FILE_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path><polyline points="13 2 13 9 20 9"></polyline></svg>'

export default class extends Controller {
  static targets = ["to", "bccField", "fileInput", "attachmentsList"]
  static values = { unsent: Boolean }

  connect() {
    this.files = []
    this._submitting = false
    this._snapshot = null
    this._beforeUnload = (e) => {
      if (this._hasChanges() && !this._submitting) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    this._beforeVisit = (e) => {
      if (this._hasChanges() && !this._submitting) {
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

  // Changes count from when someone first reaches for the form, before their input lands.
  // What a reply, forward or draft starts with isn't an edit, and neither is the editor
  // putting that body in its own HTML once it has started.
  startEditing() {
    this._snapshot ??= this._formSnapshot()
  }

  // A send that failed comes back to this same form (a morph), which still holds the message
  submitEnded(event) {
    if (!event.detail.success) this._submitting = false
  }

  // A form that came back from a failed send holds a message that hasn't gone out
  _hasChanges() {
    if (this.unsentValue) return true
    return this._snapshot !== null && this._formSnapshot() !== this._snapshot
  }

  _formSnapshot() {
    const form = new FormData(this.element)
    const fields = ["to", "cc", "bcc", "subject", "body"].map(name => form.get(name))
    const files = form.getAll("attachments[]").map(file => file.name)
    return JSON.stringify([...fields, ...files])
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

  // Picking files again replaces what the input holds, so put back the ones picked before
  handleFiles(event) {
    const newFiles = Array.from(event.target.files)
    this.files.push(...newFiles)
    this.renderAttachments()
    this.updateFileInput()
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.files.splice(index, 1)
    this.renderAttachments()
    this.updateFileInput()
  }

  renderAttachments() {
    if (!this.hasAttachmentsListTarget) return

    this.attachmentsListTarget.replaceChildren(...this.files.map((file, index) => this.attachmentItem(file, index)))
  }

  // Built with DOM APIs, so a file's name is always text, never markup
  attachmentItem(file, index) {
    const item = document.createElement("div")
    item.className = "compose-attachment-item"
    item.insertAdjacentHTML("afterbegin", FILE_ICON)

    const name = document.createElement("span")
    name.textContent = this.truncateName(file.name, 20)

    const size = document.createElement("span")
    size.className = "compose-attachment-size"
    size.textContent = formatFileSize(file.size)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "compose-attachment-remove"
    remove.dataset.index = index
    remove.dataset.action = "click->compose#removeFile"
    remove.textContent = "×"

    item.append(name, size, remove)
    return item
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
}
