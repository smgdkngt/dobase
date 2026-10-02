import { Controller } from "@hotwired/stimulus"
import { formatFileSize } from "services/file_size"
import { api } from "services/api"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["messages", "typingIndicator", "fileInput", "filePreview", "form", "replyPreview", "replyToId", "replyAuthor", "replyContent", "onlineIndicator", "imagePreviewTemplate", "filePreviewTemplate", "olderMessages", "olderMessagesTrigger", "olderMessagesPlaceholder"]
  static values = { chatId: Number, userId: Number, readUrl: String, canModerate: Boolean }

  connect() {
    this.selectedFiles = []
    this.objectUrls = []
    this.typingUsers = new Map()
    this.onlineUsers = new Set()
    this.typingTimeout = null
    this.isTyping = false
    this.markAsReadPending = false
    this.loadingOlder = false

    this.boundTurboRender = this.handleTurboRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundTurboRender)
    // Keep the bound function: removeEventListener needs the same one, or
    // every connect would leave another window listener behind.
    this.boundMarkAsRead = () => this.markAsRead()
    window.addEventListener("focus", this.boundMarkAsRead)

    this.setupActionCable()
    this.scrollToBottom()
    this.stayAtNewestMessage()
    this.markAsRead()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.boundTurboRender)
    window.removeEventListener("focus", this.boundMarkAsRead)
    this.revokeObjectUrls()
    this.channel?.unsubscribe()
    this.topObserver?.disconnect()
    this.topObserver = null
    this.sizeObserver?.disconnect()
    this.sizeObserver = null
    if (this.typingTimeout) clearTimeout(this.typingTimeout)
  }

  // Older messages
  //
  // Reaching the top asks for the page before the oldest message showing, by
  // clicking the same link a reader can click. The trigger is replaced by every
  // page that arrives, so it's watched through its target callbacks.
  olderMessagesTriggerTargetConnected(trigger) {
    if (!this.hasMessagesTarget) return

    this.topObserver ||= new IntersectionObserver(
      entries => entries.forEach(entry => { if (entry.isIntersecting) this.loadOlderMessages() }),
      { root: this.messagesTarget, rootMargin: "200px 0px 0px 0px" }
    )
    this.topObserver.observe(trigger)
  }

  olderMessagesTriggerTargetDisconnected(trigger) {
    this.topObserver?.unobserve(trigger)
  }

  loadOlderMessages() {
    if (this.loadingOlder || !this.hasOlderMessagesTriggerTarget) return
    this.olderMessagesTriggerTarget.click()
  }

  // Clicking the trigger (by hand or from the observer) swaps it for a
  // placeholder, so the wait reads as the messages that are on their way.
  loadingOlderMessages() {
    this.loadingOlder = true
    if (this.hasOlderMessagesTriggerTarget) this.olderMessagesTriggerTarget.hidden = true
    if (this.hasOlderMessagesPlaceholderTarget) this.olderMessagesPlaceholderTarget.hidden = false
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
    const follow = this.atNewestMessage
    this.typingIndicatorTarget.classList.toggle("hidden", names.length === 0)

    if (names.length > 0) {
      const text = names.length === 1 ? `${names[0]} is typing...`
        : names.length === 2 ? `${names[0]} and ${names[1]} are typing...`
        : `${names.length} people are typing...`
      this.typingIndicatorTarget.querySelector("[data-typing-text]").textContent = text
      if (follow) this.scrollToBottom()
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
      // A page of older messages goes in above what the reader is looking at:
      // hold their place instead of dropping them back at the newest message.
      if (this.isOlderMessagesStream(streamElement)) {
        const before = this.hasMessagesTarget
          ? { height: this.messagesTarget.scrollHeight, top: this.messagesTarget.scrollTop }
          : null

        fallback(streamElement)
        this.loadingOlder = false

        // Straight after the render, not in a frame callback: the three streams
        // land one after the other, and each has to correct for its own change
        // before the next one measures.
        if (before) {
          this.messagesTarget.scrollTop = before.top + (this.messagesTarget.scrollHeight - before.height)
        }
        return
      }

      // Anything else (a message, an edit, a reaction, a removal) keeps a reader who is at
      // the newest message there, and leaves one who scrolled up to read where they are.
      const follow = this.atNewestMessage
      fallback(streamElement)
      if (follow) setTimeout(() => this.scrollToBottom(), 50)
    }
  }

  // The three streams a page of older messages arrives in: the messages
  // themselves, the trigger that asks for the page before them, and the day
  // separator they take over.
  isOlderMessagesStream(streamElement) {
    const target = streamElement.getAttribute("target")
    const action = streamElement.getAttribute("action")

    if (target === "chat_older_messages") return true
    if (target === "chat_messages" && action === "prepend") return true
    return action === "remove" && target?.startsWith("chat_date_")
  }

  // Scrolling & Read receipts
  get atNewestMessage() {
    if (!this.hasMessagesTarget) return false

    const { scrollHeight, scrollTop, clientHeight } = this.messagesTarget
    return scrollHeight - scrollTop - clientHeight < 80
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  // The list gets shorter when the box under it grows (the editor arrives after the
  // page does), and its lines wrap again when the chat gets narrower (beside another
  // tool, say). Whoever was at the newest message stays there.
  stayAtNewestMessage() {
    if (!this.hasMessagesTarget) return

    let following = true
    this.messagesTarget.addEventListener("scroll", () => { following = this.atNewestMessage }, { passive: true })
    this.sizeObserver = new ResizeObserver(() => { if (following) this.scrollToBottom() })
    this.sizeObserver.observe(this.messagesTarget)
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

  // The keyboard in the messages
  //
  // The arrow keys go from message to message (arrow_keys_controller.js). Up from an
  // empty message box gets there, and down past the newest message comes back.
  composerKey(event) {
    if (event.key !== "ArrowUp" || !this.#editor?.isEmpty) return

    const messages = this.messagesTarget.querySelectorAll("[data-controller~='message']")
    const newest = messages[messages.length - 1]
    if (!newest) return

    event.preventDefault()
    if (!newest.hasAttribute("tabindex")) newest.tabIndex = -1
    newest.focus()
  }

  pastTheMessages(event) {
    if (event.detail.side === "down" && this.messagesTarget.contains(document.activeElement)) this.focusInput()
  }

  // On the message itself, not in something inside it: r replies, e edits your own,
  // Delete deletes what you may delete
  messageKey(event) {
    if (event.target !== event.currentTarget || event.metaKey || event.ctrlKey || event.altKey) return

    const message = event.currentTarget
    const press = (selector) => {
      const control = message.querySelector(selector)
      if (!control || control.closest(".hidden")) return
      event.preventDefault()
      control.click()
    }

    if (event.key === "r") {
      event.preventDefault()
      this.startReply(event)
    } else if (event.key === "e") {
      press("[data-message-edit] a")
    } else if (event.key === "Delete" || event.key === "Backspace") {
      press("[data-message-delete] a")
    }
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
        // Their own message always shows, wherever they were reading
        this.scrollToBottom()
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
