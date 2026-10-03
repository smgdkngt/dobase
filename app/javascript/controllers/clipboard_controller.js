import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  disconnect() {
    clearTimeout(this._restore)
  }

  async copy() {
    const text = this.sourceTarget.value || this.sourceTarget.textContent
    const copied = await this._write(text)

    // Left to copy by hand: the text is selected for it, where it shows
    if (!copied) this.sourceTarget.select?.()
    if (this.hasButtonTarget) this._say(copied ? "Copied!" : `Press ${/Mac|iP/.test(navigator.platform) ? "Cmd" : "Ctrl"}+C`)
  }

  // navigator.clipboard only exists on HTTPS and localhost. An install reached over plain
  // HTTP on a local network has none, and copying used to fail there without a word.
  async _write(text) {
    try {
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(text)
        return true
      }
    } catch {
      // Not allowed here either: the old way below
    }
    return this._copySelection(text)
  }

  // Inside this element, since in a dialog everything outside it can't be selected
  _copySelection(text) {
    const field = document.createElement("textarea")
    field.value = text
    field.readOnly = true
    field.setAttribute("aria-hidden", "true")
    field.style.cssText = "position: fixed; top: 0; left: 0; opacity: 0;"
    this.element.appendChild(field)
    field.select()

    try {
      return document.execCommand("copy")
    } catch {
      return false
    } finally {
      field.remove()
    }
  }

  _say(message) {
    this._label ??= this.buttonTarget.textContent
    this.buttonTarget.textContent = message
    clearTimeout(this._restore)
    this._restore = setTimeout(() => { this.buttonTarget.textContent = this._label }, 1500)
  }
}
