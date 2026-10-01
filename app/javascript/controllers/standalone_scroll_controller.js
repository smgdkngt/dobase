import { Controller } from "@hotwired/stimulus"

// A tool that fills the screen never scrolls as a page. An iPhone scrolls it anyway
// to lift a field above the keyboard, and in a home screen app leaves it scrolled
// when the keyboard goes: the top bar sits under the clock. This puts the page back.
export default class extends Controller {
  connect() {
    this._settle = this._settle.bind(this)
    document.addEventListener("focusout", this._settle)
  }

  disconnect() {
    document.removeEventListener("focusout", this._settle)
    clearTimeout(this._timer)
  }

  _settle() {
    clearTimeout(this._timer)
    // Wait for the field that may take focus next: the keyboard stays up for it
    this._timer = setTimeout(() => {
      if (window.scrollY > 0 && this._pageIsFixed() && !this._typing()) window.scrollTo(0, 0)
    }, 100)
  }

  // layout.css stops the page scrolling where a tool fills a home screen app
  _pageIsFixed() {
    return getComputedStyle(document.documentElement).overflowY === "hidden"
  }

  _typing() {
    let element = document.activeElement
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement
    return Boolean(element) && (element.isContentEditable || element.matches("input, textarea, select"))
  }
}
