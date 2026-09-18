import { Controller } from "@hotwired/stimulus"

// Large-view / slideshow gallery for a folder of pictures. Shared by the Files
// tool grid and the public share pages: both feed it the same hidden list of
// {url, name, download} entries and get the same overlay, keyboard, touch and
// slideshow behavior in return.
const SLIDESHOW_INTERVAL_MS = 4000

export default class extends Controller {
  static targets = [
    "overlay", "image", "images", "name", "counter", "downloadLink",
    "prevButton", "nextButton", "slideshowButton", "playIcon", "pauseIcon",
    "closeButton"
  ]

  connect() {
    this.currentIndex = 0
    this.images = this.hasImagesTarget
      ? Array.from(this.imagesTarget.querySelectorAll("span")).map(el => ({
          url: el.dataset.url,
          name: el.dataset.name,
          download: el.dataset.download
        }))
      : []

    this.slideshowTimer = null
    this.touchStartX = null
    this.handleKeydown = this.handleKeydown.bind(this)

    const hasMultiple = this.images.length > 1
    if (this.hasPrevButtonTarget) this.prevButtonTarget.hidden = !hasMultiple
    if (this.hasNextButtonTarget) this.nextButtonTarget.hidden = !hasMultiple
    if (this.hasSlideshowButtonTarget) this.slideshowButtonTarget.hidden = !hasMultiple
  }

  disconnect() {
    this._stopSlideshow()
    document.removeEventListener("keydown", this.handleKeydown)
  }

  open(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.currentIndex = Number.isNaN(index) ? 0 : index
    this._render()
    this.overlayTarget.hidden = false
    // The overlay is a plain element, not a <dialog>, so focus has to be moved
    // in and put back by hand.
    this._openedFrom = document.activeElement
    if (this.hasCloseButtonTarget) this.closeButtonTarget.focus()
    document.addEventListener("keydown", this.handleKeydown)
    document.body.style.overflow = "hidden"
  }

  close() {
    this._stopSlideshow()
    this.overlayTarget.hidden = true
    document.removeEventListener("keydown", this.handleKeydown)
    document.body.style.overflow = ""
    this._openedFrom?.focus?.()
    this._openedFrom = null
  }

  prev() {
    this._stopSlideshow()
    this.currentIndex = (this.currentIndex - 1 + this.images.length) % this.images.length
    this._render()
  }

  next() {
    this._stopSlideshow()
    this.currentIndex = (this.currentIndex + 1) % this.images.length
    this._render()
  }

  toggleSlideshow() {
    if (this.slideshowTimer) {
      this._stopSlideshow()
    } else {
      this._startSlideshow()
    }
  }

  touchStart(event) {
    this.touchStartX = event.changedTouches[0].clientX
  }

  touchEnd(event) {
    if (this.touchStartX === null || this.images.length <= 1) return

    const delta = event.changedTouches[0].clientX - this.touchStartX
    this.touchStartX = null
    const threshold = 40

    if (delta > threshold) this.prev()
    else if (delta < -threshold) this.next()
  }

  handleKeydown(event) {
    switch (event.key) {
      case "Escape":
        this.close()
        break
      case "ArrowLeft":
        this.prev()
        break
      case "ArrowRight":
        this.next()
        break
    }
  }

  // Private

  _render() {
    const image = this.images[this.currentIndex]
    if (!image) return

    this.imageTarget.src = image.url
    this.imageTarget.alt = image.name
    this._restartFadeIn(this.imageTarget)

    if (this.hasNameTarget) this.nameTarget.textContent = image.name
    if (this.hasCounterTarget) this.counterTarget.textContent = `${this.currentIndex + 1} / ${this.images.length}`
    if (this.hasDownloadLinkTarget) this.downloadLinkTarget.href = image.download

    this._preloadNext()
  }

  _preloadNext() {
    if (this.images.length <= 1) return

    const next = this.images[(this.currentIndex + 1) % this.images.length]
    if (next) new Image().src = next.url
  }

  _restartFadeIn(el) {
    el.classList.remove("media-fade-in")
    void el.offsetWidth
    el.classList.add("media-fade-in")
  }

  _startSlideshow() {
    if (this.images.length <= 1) return

    this.slideshowTimer = setInterval(() => {
      this.currentIndex = (this.currentIndex + 1) % this.images.length
      this._render()
    }, SLIDESHOW_INTERVAL_MS)
    this._setPlaying(true)
  }

  _stopSlideshow() {
    if (this.slideshowTimer) {
      clearInterval(this.slideshowTimer)
      this.slideshowTimer = null
    }
    this._setPlaying(false)
  }

  _setPlaying(playing) {
    if (this.hasPlayIconTarget) this.playIconTarget.hidden = playing
    if (this.hasPauseIconTarget) this.pauseIconTarget.hidden = !playing
  }
}
