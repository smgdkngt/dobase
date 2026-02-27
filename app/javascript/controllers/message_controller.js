import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    userId: Number
  }

  connect() {
    this.applyOwnershipStyling()
  }

  applyOwnershipStyling() {
    // Get current user ID from the chat controller
    const chatEl = this.element.closest("[data-chat-user-id-value]")
    if (!chatEl) return

    const currentUserId = parseInt(chatEl.dataset.chatUserIdValue)
    const messageUserId = this.userIdValue
    const isOwn = currentUserId === messageUserId

    // Store ownership for reference
    this.element.dataset.isOwn = isOwn ? "true" : "false"

    // Show delete button only for own messages
    const deleteBtn = this.element.querySelector("[data-message-delete]")
    if (deleteBtn) {
      deleteBtn.classList.toggle("hidden", !isOwn)
    }
  }
}
