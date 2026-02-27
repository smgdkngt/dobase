import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lightbox", "lightboxContent", "lightboxInfo", "images"]

  connect() {
    this.currentIndex = 0
    this.images = []

    if (this.hasImagesTarget) {
      this.images = Array.from(this.imagesTarget.querySelectorAll("span")).map(el => ({
        url: el.dataset.url,
        name: el.dataset.name,
        download: el.dataset.download
      }))
    }

    // Keyboard navigation
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  openLightbox(event) {
    event.preventDefault()
    this.currentIndex = parseInt(event.currentTarget.dataset.index, 10)
    this.showImage()
    this.lightboxTarget.hidden = false
    document.addEventListener("keydown", this.handleKeydown)
    document.body.style.overflow = "hidden"
  }

  closeLightbox() {
    this.lightboxTarget.hidden = true
    document.removeEventListener("keydown", this.handleKeydown)
    document.body.style.overflow = ""
  }

  prev() {
    this.currentIndex = (this.currentIndex - 1 + this.images.length) % this.images.length
    this.showImage()
  }

  next() {
    this.currentIndex = (this.currentIndex + 1) % this.images.length
    this.showImage()
  }

  showImage() {
    const img = this.images[this.currentIndex]
    this.lightboxContentTarget.innerHTML = `<img src="${img.url}" alt="${img.name}">`
    this.lightboxInfoTarget.innerHTML = `
      <span class="font-medium">${img.name}</span>
      <span class="opacity-70 text-sm">${this.currentIndex + 1} / ${this.images.length}</span>
    `
  }

  handleKeydown(event) {
    switch (event.key) {
      case "Escape":
        this.closeLightbox()
        break
      case "ArrowLeft":
        this.prev()
        break
      case "ArrowRight":
        this.next()
        break
    }
  }
}
