import { Controller } from "@hotwired/stimulus"

// A button that is on or off (a star) shows the other state the moment it is pressed,
// not when the server's answer is drawn. That answer draws it again as it really is.
// A link that turns it on posts and one that turns it off deletes: the method goes
// with the state, so a second press before the answer undoes the first.
export default class extends Controller {
  flip() {
    const on = this.element.getAttribute("aria-pressed") !== "true"
    this.element.setAttribute("aria-pressed", String(on))
    // After Turbo has sent this press, which it reads from the link once the click
    // reaches the document
    if (["post", "delete"].includes(this.element.dataset.turboMethod)) {
      setTimeout(() => { this.element.dataset.turboMethod = on ? "delete" : "post" })
    }
  }
}
