import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { toolId: Number }

  connect() {
    this.setupChannel()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  setupChannel() {
    this.channel = consumer.subscriptions.create(
      { channel: "DocsChannel", tool_id: this.toolIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
  }

  // The card is looked up when the word comes: the list is drawn again while it is
  // open (live_controller.js), so cards come and go
  handleMessage(data) {
    const card = this.element.querySelector(`[data-document-id="${Number(data.document_id)}"]`)
    if (!card) return

    const indicator = card.querySelector("[data-editing-indicator]")
    const userSpan = card.querySelector("[data-editing-user]")
    const label = card.querySelector("[data-editing-label]")

    switch (data.type) {
      case "locked":
        if (indicator) indicator.classList.remove("hidden")
        if (userSpan) userSpan.textContent = data.user_name
        if (label) {
          label.textContent = `${data.user_name} is editing`
          label.classList.remove("hidden")
        }
        break
      case "unlocked":
        if (indicator) indicator.classList.add("hidden")
        if (label) label.classList.add("hidden")
        break
    }
  }
}
