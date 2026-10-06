import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "banner", "card"]
  static values = { fullSrcdoc: String }

  connect() {
    this._keepThroughRefresh = this._keepThroughRefresh.bind(this)
    this.element.addEventListener("turbo:before-morph-attribute", this._keepThroughRefresh)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-attribute", this._keepThroughRefresh)
  }

  frameTargetConnected(iframe) {
    this.loadHandler = () => this.resize(iframe)
    iframe.addEventListener("load", this.loadHandler)

    // srcdoc may already be loaded by the time Stimulus connects
    if (iframe.contentDocument && iframe.contentDocument.body) {
      this.resize(iframe)
    }
  }

  frameTargetDisconnected(iframe) {
    if (this.loadHandler) {
      iframe.removeEventListener("load", this.loadHandler)
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

  // A morph refresh (the mail page's own every minute, or after starring) puts back what
  // the server drew: a frame without a height on a white card, without the images the
  // reader asked for and with the banner. The height and the card's colour stay as they
  // are: a frame that has no height for a moment scrolls a long mail back to its top.
  _keepThroughRefresh(event) {
    const target = event.target.dataset.emailFrameTarget
    const attribute = event.detail.attributeName

    if (attribute === "style" && (target === "frame" || target === "card")) return event.preventDefault()

    const kept = { frame: "srcdoc", banner: "hidden" }[target]
    if (kept && kept === attribute && this.showingImages) event.preventDefault()
  }

  // In dark mode and in a theme the email sits on a white card with a margin. An email
  // that paints its own page (a newsletter on grey, a mail in a dark theme) would show
  // that card as a white rim around it, so the card takes the email's page colour.
  _wearPageColor(doc) {
    if (!this.hasCardTarget) return

    const color = this._pageColor(doc)
    this.cardTarget.style.backgroundColor = color && color !== "rgb(255, 255, 255)" ? color : ""
  }

  // The colour an email reaches its edges in: its body's, or that of the wrapper around
  // everything in it, which is where most emails put it (a table as wide as the page)
  _pageColor(doc) {
    const painted = (element) => {
      const color = doc.defaultView.getComputedStyle(element).backgroundColor
      return /^rgba?\(.*, 0\)$|^transparent$/.test(color) ? null : color
    }

    let color = painted(doc.documentElement)
    let element = doc.body
    for (let depth = 0; element && depth < 5; depth++) {
      color = painted(element) || color
      const shown = Array.from(element.children).filter(child => child.offsetHeight > 0)
      if (shown.length !== 1 || shown[0].offsetWidth < doc.body.clientWidth * 0.95) break
      element = shown[0]
    }
    return color
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
      this._wearPageColor(doc)

      if (this.observer) this.observer.disconnect()
      this.observer = new ResizeObserver(update)
      this.observer.observe(doc.body)
    } catch (e) {
      iframe.style.height = "400px"
    }
  }
}
