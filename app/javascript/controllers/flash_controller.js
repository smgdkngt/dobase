import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]
  static values = {
    autoDismiss: { type: Boolean, default: true },
    dismissAfter: { type: Number, default: 5000 }
  }

  connect() {
    if (this.autoDismissValue) {
      this.messageTargets.forEach((message, index) => {
        setTimeout(() => {
          this.dismissMessage(message)
        }, this.dismissAfterValue + (index * 200))
      })
    }
  }

  dismiss(event) {
    const message = event.target.closest("[data-flash-target='message']")
    if (message) {
      this.dismissMessage(message)
    }
  }

  dismissMessage(message) {
    message.classList.add("flash-dismiss")
    setTimeout(() => {
      message.remove()
      if (this.messageTargets.length === 0) this.element.remove()
    }, 200)
  }
}
