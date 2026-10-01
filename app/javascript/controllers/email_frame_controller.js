import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "banner"]
  static values = { fullSrcdoc: String }

  connect() {
    this._keepImages = this._keepImages.bind(this)
    this.element.addEventListener("turbo:before-morph-attribute", this._keepImages)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-attribute", this._keepImages)
  }

  frameTargetConnected(iframe) {
    this.loadHandler = () => this.resize(iframe)
    iframe.addEventListener("load", this.loadHandler)
    // A Turbo morph refresh (e.g. after starring) resets the inline height to 0 without reloading the frame
    iframe.addEventListener("turbo:morph-element", this.loadHandler)

    // srcdoc may already be loaded by the time Stimulus connects
    if (iframe.contentDocument && iframe.contentDocument.body) {
      this.resize(iframe)
    }
  }

  frameTargetDisconnected(iframe) {
    if (this.loadHandler) {
      iframe.removeEventListener("load", this.loadHandler)
      iframe.removeEventListener("turbo:morph-element", this.loadHandler)
    }
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  // The banner is hidden rather than removed: a morph refresh matches elements by their
  // place, and with one gone it would take the frame for the banner and build a new frame
  showImages() {
    if (!this.fullSrcdocValue) return

    this.frameTarget.srcdoc = this.fullSrcdocValue
    this._shown = this.fullSrcdocValue

    if (this.hasBannerTarget) this.bannerTarget.hidden = true
  }

  // Only for the same email: after a refresh this frame can hold another message of the
  // conversation
  get showingImages() {
    return Boolean(this._shown) && this._shown === this.fullSrcdocValue
  }

  // Images the reader asked for stay through a morph refresh, which would otherwise put
  // back the frame without them, and the banner
  _keepImages(event) {
    const kept = { frame: "srcdoc", banner: "hidden" }[event.target.dataset.emailFrameTarget]

    if (kept && kept === event.detail.attributeName && this.showingImages) event.preventDefault()
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
