import { Controller } from "@hotwired/stimulus"
import { play } from "services/sound"

export default class extends Controller {
  static targets = ["message"]
  static values = {
    autoDismiss: { type: Boolean, default: true },
    dismissAfter: { type: Number, default: 5000 },
    toast: { type: Boolean, default: false }
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

  // A message that says something went wrong is heard too
  messageTargetConnected(message) {
    if (message.dataset.flashKind === "alert") play("error")
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
      // An empty inline holder would leave its margin behind. The toast holder stays:
      // messages made on the page later are put in it.
      if (this.messageTargets.length === 0 && !this.toastValue) this.element.remove()
    }, 200)
  }
}
