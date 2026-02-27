import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "trigger"]

  connect() {
    this.closeOnClickOutside = this.closeOnClickOutside.bind(this)
  }

  toggle(event) {
    if (this.contentTarget.classList.contains("hidden")) {
      this.open(event)
    } else {
      this.close()
    }
  }

  open(event) {
    this.contentTarget.classList.remove("hidden")
    this.element.classList.add("popover-open")
    this.updateAriaExpanded(true)
    // Use setTimeout to avoid closing on the same click that opened the popover
    setTimeout(() => {
      document.addEventListener("click", this.closeOnClickOutside)
    }, 0)
  }

  close() {
    this.contentTarget.classList.add("hidden")
    this.element.classList.remove("popover-open")
    this.updateAriaExpanded(false)
    document.removeEventListener("click", this.closeOnClickOutside)
  }

  updateAriaExpanded(expanded) {
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", expanded)
    }
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside)
  }
}
