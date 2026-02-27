import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "banner"]
  static values = { fullSrcdoc: String }

  frameTargetConnected(iframe) {
    this.loadHandler = () => this.resize(iframe)
    iframe.addEventListener("load", this.loadHandler)

    // srcdoc may already be loaded by the time Stimulus connects
    if (iframe.contentDocument && iframe.contentDocument.body) {
      this.resize(iframe)
    }
  }

  frameTargetDisconnected(iframe) {
    if (this.loadHandler) iframe.removeEventListener("load", this.loadHandler)
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  showImages() {
    if (!this.fullSrcdocValue) return

    const iframe = this.frameTarget
    iframe.srcdoc = this.fullSrcdocValue

    if (this.hasBannerTarget) {
      this.bannerTarget.remove()
    }
  }

  resize(iframe) {
    try {
      const doc = iframe.contentDocument
      if (!doc || !doc.body) return

      const update = () => {
        const height = doc.documentElement.scrollHeight
        if (height > 0) {
          iframe.style.height = `${height}px`
        }
      }

      update()

      if (this.observer) this.observer.disconnect()
      this.observer = new ResizeObserver(update)
      this.observer.observe(doc.body)
    } catch (e) {
      iframe.style.height = "400px"
    }
  }
}
