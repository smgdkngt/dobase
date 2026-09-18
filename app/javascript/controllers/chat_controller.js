import { Controller } from "@hotwired/stimulus"
import { formatFileSize } from "services/file_size"
import { api } from "services/api"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["messages", "typingIndicator", "fileInput", "filePreview", "form", "replyPreview", "replyToId", "replyAuthor", "replyContent", "onlineIndicator", "imagePreviewTemplate", "filePreviewTemplate"]
  static values = { chatId: Number, userId: Number, readUrl: String, canModerate: Boolean }

  connect() {
    this.selectedFiles = []
    this.objectUrls = []
    this.typingUsers = new Map()
    this.onlineUsers = new Set()
    this.typingTimeout = null
    this.isTyping = false
    this.markAsReadPending = false

    this.boundTurboRender = this.handleTurboRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundTurboRender)
    // Keep the bound function: removeEventListener needs the same one, or
    // every connect would leave another window listener behind.
    this.boundMarkAsRead = () => this.markAsRead()
    window.addEventListener("focus", this.boundMarkAsRead)

    this.setupActionCable()
    this.scrollToBottom()
    this.markAsRead()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundTurboRender)
    window.removeEventListener("focus", this.boundMarkAsRead)
    this.revokeObjectUrls()
    this.channel?.unsubscribe()
    if (this.typingTimeout) clearTimeout(this.typingTimeout)
  }

  // ActionCable
  setupActionCable() {
    this.channel = consumer.subscriptions.create(
      { channel: "ChatChannel", chat_id: this.chatIdValue },
      {
        received: (data) => this.handleChannelMessage(data),
        connected: () => setTimeout(() => this.channel.perform("request_presence"), 500),
        disconnected: () => {}
      }
    )
  }

  handleChannelMessage(data) {
    // Presence is counted per server process, so one of our own tabs closing on
    // another process can mark us offline while we're still here. Say hello
    // again rather than letting everyone else think we left.
    if (data.type === "presence" && data.status === "offline" && data.user_id === this.userIdValue) {
      this.channel?.perform("announce_presence")
    }

    if (data.user_id === this.userIdValue) return

    switch (data.type) {
      case "typing":
        this.typingUsers.set(data.user_id, data.user_name)
        this.updateTypingIndicator()
        setTimeout(() => {
          this.typingUsers.delete(data.user_id)
          this.updateTypingIndicator()
        }, 3000)
        break
      case "stop_typing":
        this.typingUsers.delete(data.user_id)
        this.updateTypingIndicator()
        break
      case "presence":
        // Answer a newcomer's hello, so they see who was already here
        if (data.status === "online" && data.hello) this.channel?.perform("announce_presence")
        data.status === "online"
          ? this.onlineUsers.add(data.user_id)
          : this.onlineUsers.delete(data.user_id)
        if (data.status === "offline") {
          this.typingUsers.delete(data.user_id)
          this.updateTypingIndicator()
        }
        this.updateOnlineIndicators()
        break
    }
  }

  updateTypingIndicator() {
    if (!this.hasTypingIndicatorTarget) return

    const names = Array.from(this.typingUsers.values())
    this.typingIndicatorTarget.classList.toggle("hidden", names.length === 0)

    if (names.length > 0) {
      const text = names.length === 1 ? `${names[0]} is typing...`
        : names.length === 2 ? `${names[0]} and ${names[1]} are typing...`
        : `${names.length} people are typing...`
      this.typingIndicatorTarget.querySelector("[data-typing-text]").textContent = text
      this.scrollToBottom()
    }
  }

  updateOnlineIndicators() {
    this.onlineIndicatorTargets.forEach(el => {
      el.classList.toggle("hidden", !this.onlineUsers.has(parseInt(el.dataset.userId)))
    })
  }

  typing() {
    if (!this.channel || this.isTyping) return
    this.isTyping = true
    this.channel.perform("typing")
    if (this.typingTimeout) clearTimeout(this.typingTimeout)
    this.typingTimeout = setTimeout(() => this.stopTyping(), 2000)
  }

  stopTyping() {
    if (!this.channel || !this.isTyping) return
    this.isTyping = false
    this.channel.perform("stop_typing")
  }

  // Turbo Stream handling
  handleTurboRender(event) {
    const fallback = event.detail.render
    event.detail.render = (streamElement) => {
      fallback(streamElement)
      setTimeout(() => this.scrollToBottom(), 50)
    }
  }

  // Scrolling & Read receipts
  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  async markAsRead() {
    if (!this.hasReadUrlValue || this.markAsReadPending) return
    this.markAsReadPending = true
    try {
      await api(this.readUrlValue, "POST")
    } catch (e) {
      console.error("Failed to mark chat as read:", e)
    } finally {
      this.markAsReadPending = false
    }
  }

  // File handling
  openFilePicker() { this.fileInputTarget.click() }

  filesSelected(event) {
    const files = Array.from(event.target.files)
    if (files.length === 0) return
    this.selectedFiles = files
    this.renderFilePreview()
  }

  removeFile(event) {
    this.selectedFiles.splice(parseInt(event.currentTarget.dataset.index), 1)
    this.syncFileInput()
    this.renderFilePreview()
  }

  clearFiles() {
    this.revokeObjectUrls()
    this.selectedFiles = []
    if (this.hasFileInputTarget) this.fileInputTarget.value = ""
    this.renderFilePreview()
  }

  syncFileInput() {
    const dt = new DataTransfer()
    this.selectedFiles.forEach(f => dt.items.add(f))
    this.fileInputTarget.files = dt.files
  }

  revokeObjectUrls() {
    this.objectUrls.forEach(url => URL.revokeObjectURL(url))
    this.objectUrls = []
  }

  renderFilePreview() {
    if (!this.hasFilePreviewTarget) return
    this.revokeObjectUrls()
    this.filePreviewTarget.innerHTML = ""

    if (this.selectedFiles.length === 0) {
      this.filePreviewTarget.classList.add("hidden")
      return
    }

    this.filePreviewTarget.classList.remove("hidden")

    this.selectedFiles.forEach((file, index) => {
      const isImage = file.type.startsWith("image/") && !file.type.includes("svg")
      const template = isImage ? this.imagePreviewTemplateTarget : this.filePreviewTemplateTarget
      const clone = template.content.cloneNode(true)
      const container = clone.firstElementChild

      container.querySelector("[data-action]").dataset.index = index

      if (isImage) {
        const url = URL.createObjectURL(file)
        this.objectUrls.push(url)
        const img = container.querySelector("img")
        img.src = url
        img.alt = file.name
      } else {
        container.querySelector("[data-filename]").textContent = file.name
        container.querySelector("[data-filesize]").textContent = formatFileSize(file.size)
      }

      this.filePreviewTarget.appendChild(clone)
    })
  }

  // Reply handling
  startReply(event) {
    const msg = this.element.querySelector(`[data-message-id="${event.currentTarget.dataset.messageId}"]`)
    if (!msg) return

    if (this.hasReplyToIdTarget) this.replyToIdTarget.value = msg.dataset.messageId
    if (this.hasReplyAuthorTarget) this.replyAuthorTarget.textContent = `Replying to ${msg.dataset.messageAuthor}`
    if (this.hasReplyContentTarget) this.replyContentTarget.textContent = msg.dataset.messageContent || "[File attachment]"
    if (this.hasReplyPreviewTarget) this.replyPreviewTarget.classList.remove("hidden")
    this.#editor?.commands.focus()
  }

  cancelReply() {
    if (this.hasReplyToIdTarget) this.replyToIdTarget.value = ""
    if (this.hasReplyPreviewTarget) this.replyPreviewTarget.classList.add("hidden")
  }

  focusInput() {
    this.#editor?.commands.focus()
  }

  // Form submission
  submit(event) {
    const editor = this.#editor
    // TipTap's Editor exposes isEmpty, not isBlank — isBlank is always
    // undefined, so !editor.isBlank was always true and let empty sends through.
    const hasText = editor && !editor.isEmpty
    const hasFiles = this.selectedFiles.length > 0

    if (!hasText && !hasFiles) {
      event.preventDefault()
      return
    }

    this.stopTyping()

    event.target.addEventListener("turbo:submit-end", (e) => {
      if (e.detail.success) {
        const richTextInput = this.element.querySelector("[data-controller='rich-text-input']")
        const controller = this.application.getControllerForElementAndIdentifier(richTextInput, "rich-text-input")
        if (controller) controller.clear()
        this.clearFiles()
        this.cancelReply()
      }
    }, { once: true })
  }

  // The TipTap editor instance, not the <rhino-editor> element itself — the
  // actual editable content lives in its shadow DOM, so plain .focus() on
  // the custom element doesn't move the cursor into it. Use TipTap's own
  // focus command instead, same as rich_text_input_controller does for clear.
  get #editor() {
    return this.element.querySelector("rhino-editor")?.editor
  }
}
