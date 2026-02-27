import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "preview", "icon"]
  static values = { open: Boolean }

  connect() {
    this.render()
  }

  toggle() {
    this.openValue = !this.openValue
    this.render()
  }

  render() {
    this.contentTarget.classList.toggle("hidden", !this.openValue)
    if (this.hasPreviewTarget) this.previewTarget.classList.toggle("hidden", this.openValue)
    if (this.hasIconTarget) this.iconTarget.classList.toggle("rotated", this.openValue)
  }
}
