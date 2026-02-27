import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.closeOnNavigate = this.close.bind(this)
    this.handleBeforeRender = this.handleBeforeRender.bind(this)
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)

    document.addEventListener("turbo:visit", this.closeOnNavigate)
    document.addEventListener("turbo:morph", this.closeOnNavigate)
    document.addEventListener("turbo:before-morph", this.closeOnNavigate)
    document.addEventListener("turbo:before-stream-render", this.handleBeforeRender)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:visit", this.closeOnNavigate)
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

  handleBeforeRender(event) {
    // Close modal before turbo stream renders (handles refresh action)
    const stream = event.target
    if (stream.action === "refresh") {
      this.close()
    }
  }

  handleSubmitEnd(event) {
    // Close modal if form/link submission inside this modal was successful,
    // but NOT if the form targets a turbo-frame within this modal (e.g. comments)
    if (event.detail.success) {
      const target = event.target
      if (this.element.contains(target)) {
        const frameId = target.dataset?.turboFrame || target.getAttribute("data-turbo-frame")
        if (frameId && frameId !== "_top" && this.element.querySelector(`#${frameId}`)) {
          return // frame update within the modal, don't close
        }
        this.close()
      }
    }
  }
}
