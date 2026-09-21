import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.closeOnNavigate = this.close.bind(this)
    this.closeForVisit = this.closeForNavigation.bind(this)
    this.handleBeforeRender = this.handleBeforeRender.bind(this)
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)

    document.addEventListener("turbo:visit", this.closeForVisit)
    document.addEventListener("turbo:morph", this.closeOnNavigate)
    document.addEventListener("turbo:before-morph", this.closeOnNavigate)
    document.addEventListener("turbo:before-stream-render", this.handleBeforeRender)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:visit", this.closeForVisit)
    document.removeEventListener("turbo:morph", this.closeOnNavigate)
    document.removeEventListener("turbo:before-morph", this.closeOnNavigate)
    document.removeEventListener("turbo:before-stream-render", this.handleBeforeRender)
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  open() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  // The page is going somewhere else. Whoever listens for this dialog closing
  // must not start a visit of its own (the board and todo pages go back to
  // themselves when their dialog closes), or it would win over the one that is
  // under way; data-closed-for-navigation tells them.
  closeForNavigation() {
    if (!this.element.open) return

    this.element.dataset.closedForNavigation = ""
    this.element.close()
  }

  handleBeforeRender(event) {
    // Close modal before turbo stream renders (handles refresh action)
    const stream = event.target
    if (stream.action === "refresh") {
      this.close()
    }
  }

  handleSubmitEnd(event) {
    // Close modal if form/link submission inside this modal was successful,
    // but NOT if the form updates a turbo-frame within this modal (e.g. comments,
    // or a nested tab frame like access tokens) — whether that frame is named via
    // an explicit data-turbo-frame or is just the form's nearest ancestor frame.
    if (event.detail.success) {
      const target = event.target
      if (this.element.contains(target)) {
        const frameId = target.dataset?.turboFrame || target.getAttribute("data-turbo-frame")
        if (frameId !== "_top") {
          const frame = frameId ? this.element.querySelector(`#${frameId}`) : target.closest("turbo-frame")
          if (frame && this.element.contains(frame)) {
            return // frame update within the modal, don't close
          }
        }
        this.close()
      }
    }
  }
}
