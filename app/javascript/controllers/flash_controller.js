import { Controller } from "@hotwired/stimulus"
import { play } from "services/sound"
import { showFlash, dismissLater, SHOWN_FOR_WITH_UNDO } from "services/flash"

// What a page said that the window left before drawing it (workspace_gate.js)
const CARRIED = "dobase:flash"

export default class extends Controller {
  static targets = ["message"]
  static values = {
    autoDismiss: { type: Boolean, default: true },
    dismissAfter: { type: Number, default: 5000 },
    toast: { type: Boolean, default: false }
  }

  connect() {
    if (this.toastValue) this.sayCarried()
    if (this.autoDismissValue) {
      this.messageTargets.forEach((message, index) => {
        const shownFor = message.querySelector("[data-flash-undo]") ? SHOWN_FOR_WITH_UNDO : this.dismissAfterValue
        dismissLater(message, shownFor + (index * 200), () => this.dismissMessage(message))
      })
    }
  }

  sayCarried() {
    let carried = []
    try {
      carried = JSON.parse(sessionStorage.getItem(CARRIED)) || []
      sessionStorage.removeItem(CARRIED)
    } catch {
      // Nothing kept, or nothing readable
    }
    for (const [ kind, message ] of carried) showFlash(message, kind)
  }

  // A message that says something went wrong is heard too
  messageTargetConnected(message) {
    if (message.dataset.flashKind === "alert") play("error")
  }

  dismiss(event) {
    // The Undo button is pressed, not the message
    if (event.target.closest("[data-flash-undo]")) return

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
