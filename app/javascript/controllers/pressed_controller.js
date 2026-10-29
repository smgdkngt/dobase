import { Controller } from "@hotwired/stimulus"
import { apiDelete, apiPost } from "services/api"
import { visitPage } from "services/tile"

// A button that is on or off (a star) shows the other state the moment it is pressed,
// not when the server's answer is drawn. Its link turns it on with a POST and off with
// a DELETE; the presses go to the server one after the other, in the order they were
// made, and the page is drawn again once the last one is answered.
// Not as a visit: Turbo cancels a press it is still sending when the answer to the one
// before arrives, which the server has done all the same, and then draws that earlier
// answer, so two quick presses left a star shown that was off.
export default class extends Controller {
  flip(event) {
    event.preventDefault()
    const on = this.element.getAttribute("aria-pressed") !== "true"
    this.element.setAttribute("aria-pressed", String(on))

    const url = this.element.getAttribute("href")
    const press = (this.pressing || Promise.resolve()).then(() => on ? apiPost(url) : apiDelete(url))
    this.pressing = press
    press.then(() => {
      if (this.pressing === press && this.element.isConnected) visitPage(this.element)
    })
  }
}
