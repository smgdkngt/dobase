import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "commandPalette"]

  connect() {
    this.boundHandleKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandleKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleKey)
  }

  handleKey(event) {
    // Escape closes the topmost open dialog — prevent hotkey handlers from stealing it
    if (event.key === "Escape") {
      const openDialog = document.querySelector("dialog[open]")
      if (openDialog) {
        event.stopImmediatePropagation()
        openDialog.close()
        return
      }
    }

    if (this.isTyping(event.target)) return
    if (event.key === "?" || (event.key === "/" && event.shiftKey)) {
      event.preventDefault()
      this.toggleDialog()
    }
  }

  toggleDialog() {
    if (!this.hasDialogTarget) return
    this.dialogTarget.open ? this.dialogTarget.close() : this.dialogTarget.showModal()
  }

  openCommandPalette() {
    if (!this.hasCommandPaletteTarget) return
    const palette = this.commandPaletteTarget
    const controller = this.application.getControllerForElementAndIdentifier(palette, "command-palette")
    controller?.open()
  }

  isTyping(el) {
    return el?.tagName?.match(/^(INPUT|TEXTAREA|SELECT)$/i) || el?.isContentEditable
  }
}
