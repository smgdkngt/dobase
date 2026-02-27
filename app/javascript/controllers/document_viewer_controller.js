import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["title", "content", "lockStatus", "editedStatus", "editButton"]
  static values = { documentId: Number }

  connect() {
    this.setupChannel()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  setupChannel() {
    this.channel = consumer.subscriptions.create(
      { channel: "DocumentChannel", document_id: this.documentIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
  }

  handleMessage(data) {
    switch (data.type) {
      case "content_updated":
        this.updateContent(data)
        break
      case "locked":
        this.showLocked(data.user_name)
        break
      case "unlocked":
        this.showUnlocked(data.user_name)
        break
    }
  }

  updateContent(data) {
    if (this.hasTitleTarget && data.title) {
      this.titleTarget.textContent = data.title
    }

    if (this.hasContentTarget && data.content_html !== undefined) {
      this.contentTarget.innerHTML = data.content_html || ""
    }

    if (this.hasEditedStatusTarget && data.edited_by) {
      this.editedStatusTarget.textContent = `Edited ${data.edited_at} by ${data.edited_by}`
    }
  }

  showLocked(userName) {
    if (this.hasLockStatusTarget) {
      this.lockStatusTarget.innerHTML = `
        <span class="w-2 h-2 bg-warning rounded-full animate-pulse" aria-hidden="true"></span>
        ${userName} is editing
      `
      this.lockStatusTarget.classList.remove("hidden")
    }

    if (this.hasEditedStatusTarget) {
      this.editedStatusTarget.classList.add("hidden")
    }

    if (this.hasEditButtonTarget) {
      this.editButtonTarget.classList.add("opacity-50", "pointer-events-none")
      this.editButtonTarget.classList.remove("btn-primary")
      this.editButtonTarget.classList.add("btn-secondary")
      this.editButtonTarget.setAttribute("aria-disabled", "true")
      this.editButtonTarget.setAttribute("title", `${userName} is currently editing`)
    }
  }

  showUnlocked(userName) {
    if (this.hasLockStatusTarget) {
      this.lockStatusTarget.classList.add("hidden")
    }

    if (this.hasEditedStatusTarget) {
      if (userName) {
        this.editedStatusTarget.textContent = `Edited just now by ${userName}`
      }
      this.editedStatusTarget.classList.remove("hidden")
    }

    if (this.hasEditButtonTarget) {
      this.editButtonTarget.classList.remove("opacity-50", "pointer-events-none")
      this.editButtonTarget.classList.remove("btn-secondary")
      this.editButtonTarget.classList.add("btn-primary")
      this.editButtonTarget.removeAttribute("aria-disabled")
      this.editButtonTarget.removeAttribute("title")
    }
  }
}
