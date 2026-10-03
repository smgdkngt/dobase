import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "commandPalette"]

  // On the root element, not the document: a key gets here after everything in the page
  // has had it, and before the shortcut library, which listens on the document. Which of
  // the two started listening first no longer matters.
  connect() {
    this.boundHandleKey = this.handleKey.bind(this)
    document.documentElement.addEventListener("keydown", this.boundHandleKey)
  }

  disconnect() {
    document.documentElement.removeEventListener("keydown", this.boundHandleKey)
  }

  handleKey(event) {
    if (event.key === "Escape") {
      // Something nearer the key took it already: the list of people to mention closes on
      // Escape, and the card around it stays open
      if (event.defaultPrevented) return

      // In a field on the page it lets go of the field: the keyboard is back with the
      // page, and the arrow keys go on from there. In a dialog or a menu Escape is
      // what closes it, as everywhere.
      const field = event.composedPath()[0] || event.target
      if (this.isTyping(field) && !field.closest?.("dialog[open], [popover]:popover-open")) {
        event.preventDefault()
        event.stopPropagation()
        return field.blur()
      }

      // The browser closes the dialog on top by itself, and only that one. Closing one
      // here as well closed a second: the card under the command palette. Escape just
      // stops here, so the page's own Escape shortcuts don't fire behind a dialog (and
      // don't cancel the key, which would keep the browser from closing it).
      if (document.querySelector("dialog[open]")) {
        event.stopPropagation()
        return
      }
    }

    // Where the key was really typed: a field inside a shadow root (the editor's link
    // box) shows up here as the editor around it
    if (this.isTyping(event.composedPath()[0] || event.target)) return
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
