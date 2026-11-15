import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "preview", "icon"]
  // keep: what shows stays as it is when the page draws itself again, whatever the
  // server drew (a conversation, whose unread messages open once and are read by then)
  static values = { open: Boolean, keep: Boolean }

  connect() {
    this._afterMorph = this._afterMorph.bind(this)
    this._keepThroughRefresh = this._keepThroughRefresh.bind(this)
    this.element.addEventListener("turbo:morph-element", this._afterMorph)
    this.element.addEventListener("turbo:before-morph-attribute", this._keepThroughRefresh)
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("turbo:morph-element", this._afterMorph)
    this.element.removeEventListener("turbo:before-morph-attribute", this._keepThroughRefresh)
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

  // Kept, the morph leaves alone what says open or closed, so nothing that is read
  // closes for a moment (which would scroll the conversation it is in)
  _keepThroughRefresh(event) {
    if (!this.keepValue) return

    const { target, detail } = event
    if (target === this.element && detail.attributeName === `data-${this.identifier}-open-value`) return event.preventDefault()

    const shown = [...this.contentTargets, ...this.previewTargets, ...this.iconTargets]
    if (detail.attributeName === "class" && shown.includes(target)) event.preventDefault()
  }

  // What shows while it is open can be in several places (a mail's text, and above it
  // everyone it went to); the previews stand in for it while it is closed
  render() {
    this.contentTargets.forEach(content => content.classList.toggle("hidden", !this.openValue))
    this.previewTargets.forEach(preview => preview.classList.toggle("hidden", this.openValue))
    if (this.hasIconTarget) this.iconTarget.classList.toggle("rotate-180", this.openValue)
  }
}
