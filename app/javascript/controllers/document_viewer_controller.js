import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["title", "content", "lockStatus", "editorName", "editedStatus"]
  static values = { documentId: Number, userId: Number }

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
        // Your own editor, in another tab, is nobody else editing
        if (data.user_id === this.userIdValue) {
          this.showUnlocked()
        } else {
          this.showLocked(data.user_name)
        }
        break
      case "unlocked":
        this.showUnlocked()
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

  // Several people can write in a document at once, so someone else in the
  // editor is only news: Edit stays open to join them. The name comes from
  // another collaborator and goes in as text, never as markup.
  showLocked(userName) {
    if (this.hasEditorNameTarget) this.editorNameTarget.textContent = userName
    if (this.hasLockStatusTarget) this.lockStatusTarget.classList.remove("hidden")
    if (this.hasEditedStatusTarget) this.editedStatusTarget.classList.add("hidden")
  }

  showUnlocked() {
    if (this.hasLockStatusTarget) this.lockStatusTarget.classList.add("hidden")
    if (this.hasEditedStatusTarget && this.editedStatusTarget.textContent.trim()) {
      this.editedStatusTarget.classList.remove("hidden")
    }
  }
}
