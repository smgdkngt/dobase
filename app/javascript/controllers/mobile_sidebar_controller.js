import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay"]

  toggle() {
    this.sidebarTarget.classList.toggle("open")
    this.overlayTarget.classList.toggle("active")
    document.body.classList.toggle("overflow-hidden")
  }

  close() {
    this.sidebarTarget.classList.remove("open")
    this.overlayTarget.classList.remove("active")
    document.body.classList.remove("overflow-hidden")
  }

  // Close sidebar when clicking a link (for navigation)
  navigate() {
    if (window.innerWidth < 768) {
      this.close()
    }
  }
}
