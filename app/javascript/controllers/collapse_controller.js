import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "preview", "icon"]
  static values = { open: Boolean }

  connect() {
    this._afterMorph = this._afterMorph.bind(this)
    this.element.addEventListener("turbo:morph-element", this._afterMorph)
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("turbo:morph-element", this._afterMorph)
  }

  toggle() {
    this.openValue = !this.openValue
    this._chosen = this.openValue
    this.render()
  }

  // A morph refresh puts back what the server rendered without connecting again, so
  // what the reader opened or closed themselves is applied once more
  _afterMorph(event) {
    if (event.target !== this.element) return

    if (this._chosen !== undefined) this.openValue = this._chosen
    this.render()
  }

  render() {
    this.contentTarget.classList.toggle("hidden", !this.openValue)
    if (this.hasPreviewTarget) this.previewTarget.classList.toggle("hidden", this.openValue)
    if (this.hasIconTarget) this.iconTarget.classList.toggle("rotated", this.openValue)
  }
}
