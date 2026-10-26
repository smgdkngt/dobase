import { Controller } from "@hotwired/stimulus"

// A button that is on or off (a star) shows the other state the moment it is pressed,
// not when the server's answer is drawn. That answer draws it again as it really is.
export default class extends Controller {
  flip() {
    this.element.setAttribute("aria-pressed", this.element.getAttribute("aria-pressed") === "true" ? "false" : "true")
  }
}
