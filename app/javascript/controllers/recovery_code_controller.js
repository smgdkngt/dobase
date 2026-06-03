import { Controller } from "@hotwired/stimulus"

// Switches the 2FA verification field from a 6-digit OTP to accept a longer
// recovery code, and hides the "use a recovery code" prompt.
export default class extends Controller {
  static targets = ["field", "prompt"]

  reveal() {
    this.fieldTarget.removeAttribute("inputmode")
    this.fieldTarget.setAttribute("maxlength", "20")
    this.fieldTarget.focus()
    this.promptTarget.classList.add("hidden")
  }
}
