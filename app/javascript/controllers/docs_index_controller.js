import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { toolId: Number }

  connect() {
    this.documentCards = new Map()
    this.cacheCards()
    this.setupChannel()
  }

  disconnect() {
    this.documentCards.clear()
    this.channel?.unsubscribe()
  }

  cacheCards() {
    this.element.querySelectorAll("[data-document-id]").forEach(card => {
      const id = card.dataset.documentId
      this.documentCards.set(id, {
        indicator: card.querySelector("[data-editing-indicator]"),
        userSpan: card.querySelector("[data-editing-user]"),
        label: card.querySelector("[data-editing-label]")
      })
    })
  }

  setupChannel() {
    this.channel = consumer.subscriptions.create(
      { channel: "DocsChannel", tool_id: this.toolIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
  }

  handleMessage(data) {
    const elements = this.documentCards.get(String(data.document_id))
    if (!elements) return

    const { indicator, userSpan, label } = elements

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
