import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["form", "title", "editor", "saveIndicator"]
  static values = {
    documentId: Number,
    saveUrl: String
  }

  connect() {
    this.saveTimeout = null
    this.isSaving = false
    this.pendingSave = false
    this.lastSavedTitle = this.titleTarget.value

    this.setupChannel()
    this.setupKeyboardShortcuts()
  }

  disconnect() {
    if (this.saveTimeout) clearTimeout(this.saveTimeout)
    if (this.lockInterval) clearInterval(this.lockInterval)
    this.channel?.unsubscribe()
    this.removeKeyboardShortcuts()
  }

  setupChannel() {
    // Clear any existing interval first
    if (this.lockInterval) clearInterval(this.lockInterval)

    this.channel = consumer.subscriptions.create(
      { channel: "DocumentChannel", document_id: this.documentIdValue },
      {
        connected: () => {
          this.channel.perform("start_editing")
          this.refreshLock()
        },
        disconnected: () => {
          this.showSaveIndicator("Reconnecting...", true)
        },
        rejected: () => {
          this.showSaveIndicator("Access denied", true)
        },
        received: (data) => {
          if (data.type === "lock_rejected") {
            this.showSaveIndicator(`${data.locked_by} is editing`, true)
          }
        }
      }
    )

    this.lockInterval = setInterval(() => this.refreshLock(), 60000)
  }

  refreshLock() {
    this.channel?.perform("refresh_lock")
  }

  setupKeyboardShortcuts() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  removeKeyboardShortcuts() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "s") {
      event.preventDefault()
      if (this.saveTimeout) clearTimeout(this.saveTimeout)
      this.save()
    }
  }

  scheduleAutoSave() {
    if (this.saveTimeout) clearTimeout(this.saveTimeout)
    this.showSaveIndicator("Editing...")
    this.saveTimeout = setTimeout(() => this.save(), 2000)
  }

  async save() {
    if (this.isSaving) {
      this.pendingSave = true
      return
    }

    this.isSaving = true
    this.pendingSave = false
    this.showSaveIndicator("Saving...")

    try {
      const formData = new FormData(this.formTarget)
      formData.set("docs_document[title]", this.titleTarget.value)

      const response = await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        },
        body: formData
      })

      if (response.ok) {
        this.lastSavedTitle = this.titleTarget.value
        this.showSaveIndicator("Saved")
      } else {
        this.showSaveIndicator("Save failed", true)
      }
    } catch {
      this.showSaveIndicator("Save failed", true)
    } finally {
      this.isSaving = false

      if (this.pendingSave) {
        setTimeout(() => this.save(), 100)
      }
    }
  }

  showSaveIndicator(status, isError = false) {
    if (!this.hasSaveIndicatorTarget) return

    const indicator = this.saveIndicatorTarget
    indicator.classList.remove("text-error", "text-success")

    if (isError) {
      indicator.classList.add("text-error")
    } else if (status === "Saved") {
      indicator.classList.add("text-success")
    }

    indicator.textContent = status
  }
}
