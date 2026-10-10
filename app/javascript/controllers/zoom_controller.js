import { Controller } from "@hotwired/stimulus"
import { within, stepIn, stepOut, wheelFactor, scrollToKeep, percent } from "services/zoom"
import { tileOf, zoomOf } from "services/tile"

// Zooming in on a file where it is shown (components/zoom_controls beside a
// components/media_preview). By the buttons, by plus, minus and zero, by the wheel with
// Ctrl or Cmd (which is also what a pinch on a trackpad comes as), by two fingers on a
// screen, and a double click on a picture. What is bigger than its place scrolls there:
// with a finger as anything scrolls, a picture also by dragging it with the mouse.
//
// What it does to the file goes by what the file is:
//   picture   an <img>: given a size of its own, so many times the size it fitted in
//   scroller  what scrolls. Text and tables are their own scroller, and their contents
//             are drawn larger or smaller with the CSS zoom (--file-zoom, components.css)
//   frame     a pdf in the browser's own viewer: the frame's contents are zoomed, and
//             the scrolling stays the viewer's
//
// It starts at fit, and a next file is another element with a controller of its own, so
// that one starts at fit too.
const PICTURE = { min: 1, max: 8 }
const PAGE = { min: 0.5, max: 4 }

export default class extends Controller {
  static targets = ["picture", "scroller", "frame", "controls", "level", "in", "out"]

  connect() {
    this.zoom = 1
    this.limits = this.hasPictureTarget ? PICTURE : PAGE

    for (const name of ["toggled", "wheeled", "touched", "pinched", "released", "gestured", "held", "dragged", "dropped", "keyed"]) {
      this[name] = this[name].bind(this)
    }
    // Not as actions in the view: the wheel and a finger's move have to be refusable
    this.element.addEventListener("wheel", this.wheeled, { passive: false })
    this.element.addEventListener("touchstart", this.touched, { passive: true })
    this.element.addEventListener("touchmove", this.pinched, { passive: false })
    this.element.addEventListener("touchend", this.released)
    this.element.addEventListener("touchcancel", this.released)
    this.element.addEventListener("gesturestart", this.gestured)
    this.element.addEventListener("gesturechange", this.gestured)
    this.element.addEventListener("pointerdown", this.held)
    this.element.addEventListener("dblclick", this.toggled)
    document.addEventListener("keydown", this.keyed)

    this.controlsTarget.hidden = !this.zooms
    this.draw()
  }

  disconnect() {
    this.element.removeEventListener("wheel", this.wheeled)
    this.element.removeEventListener("touchstart", this.touched)
    this.element.removeEventListener("touchmove", this.pinched)
    this.element.removeEventListener("touchend", this.released)
    this.element.removeEventListener("touchcancel", this.released)
    this.element.removeEventListener("gesturestart", this.gestured)
    this.element.removeEventListener("gesturechange", this.gestured)
    this.element.removeEventListener("pointerdown", this.held)
    this.element.removeEventListener("dblclick", this.toggled)
    document.removeEventListener("keydown", this.keyed)
    this.dropped()
    cancelAnimationFrame(this.pending)
  }

  // A file that can only be downloaded has nothing to zoom in on
  get zooms() {
    return this.hasPictureTarget || this.hasScrollerTarget || this.hasFrameTarget
  }

  zoomIn() {
    this.zoomTo(stepIn(this.zoom, this.limits))
  }

  zoomOut() {
    this.zoomTo(stepOut(this.zoom, this.limits))
  }

  fit() {
    this.zoomTo(1)
  }

  // A double click on a picture: in, and back to fit from wherever it was
  toggled(event) {
    if (!this.hasPictureTarget || event.target !== this.pictureTarget) return

    this.zoomTo(this.zoom === 1 ? 2 : 1, { x: event.clientX, y: event.clientY })
  }

  // at: the place on the screen that keeps what it shows. Without one, the middle.
  zoomTo(wanted, at = null) {
    const to = within(wanted, this.limits)
    if (!this.zooms || to === this.zoom || !this.measured()) return

    const scroller = this.hasScrollerTarget ? this.scrollerTarget : null
    const from = this.zoom
    const point = at || (scroller && middleOf(scroller))
    const before = scroller && this.origin(scroller)

    this.zoom = to
    this.draw()

    if (scroller) {
      const after = this.origin(scroller)
      const scale = zoomOf(scroller)
      scroller.scrollLeft += scrollToKeep(before.x, after.x, point.x, to / from) / scale
      scroller.scrollTop += scrollToKeep(before.y, after.y, point.y, to / from) / scale
    }
  }

  // A pinch and a wheel say many times a moment how far: the last one before the page
  // is drawn again is the one that counts
  zoomSoon(wanted, at) {
    this.wanted = { zoom: within(wanted, this.limits), at }
    this.pending ||= requestAnimationFrame(() => {
      this.pending = null
      this.zoomTo(this.wanted.zoom, this.wanted.at)
      this.wanted = null
    })
  }

  // The zoom a pinch or the wheel goes on from: the one asked for, when it isn't drawn yet
  get asked() {
    return this.wanted ? this.wanted.zoom : this.zoom
  }

  draw() {
    const zoomed = this.zoom !== 1
    this.element.toggleAttribute("data-zoomed", zoomed)

    if (this.hasPictureTarget) {
      const style = this.pictureTarget.style
      style.width = zoomed ? `${this.fitted.width * this.zoom}px` : ""
      style.height = zoomed ? `${this.fitted.height * this.zoom}px` : ""
      style.maxWidth = style.maxHeight = zoomed ? "none" : ""
    } else if (this.hasScrollerTarget) {
      if (zoomed) this.scrollerTarget.style.setProperty("--file-zoom", this.zoom)
      else this.scrollerTarget.style.removeProperty("--file-zoom")
    }
    if (this.hasFrameTarget) this.frameTarget.style.zoom = zoomed ? this.zoom : ""

    this.levelTarget.textContent = percent(this.zoom)
    this.levelTarget.setAttribute("aria-label", `Zoom ${percent(this.zoom)}, back to fit`)
    this.levelTarget.setAttribute("aria-disabled", !zoomed)
    this.inTarget.setAttribute("aria-disabled", this.zoom >= this.limits.max)
    this.outTarget.setAttribute("aria-disabled", this.zoom <= this.limits.min)
  }

  // The size a picture fits in is the size it has before it is first zoomed. One that
  // hasn't arrived has none yet, and waits.
  measured() {
    if (!this.hasPictureTarget || this.zoom !== 1) return true

    const { offsetWidth: width, offsetHeight: height } = this.pictureTarget
    this.fitted = { width, height }
    return width > 0 && height > 0
  }

  // Where on the screen what is shown begins: the picture's corner, or where the first
  // of a text would be if nothing of it were scrolled away
  origin(scroller) {
    const box = (this.hasPictureTarget ? this.pictureTarget : scroller).getBoundingClientRect()
    if (this.hasPictureTarget) return { x: box.left, y: box.top }

    const scale = zoomOf(scroller)
    return { x: box.left - scroller.scrollLeft * scale, y: box.top - scroller.scrollTop * scale }
  }

  // The wheel

  wheeled(event) {
    if (!(event.ctrlKey || event.metaKey) || !this.zooms) return

    // Also where it can go no further: the browser would zoom the whole page instead
    event.preventDefault()
    this.zoomSoon(this.asked * wheelFactor(event.deltaY, event.deltaMode), { x: event.clientX, y: event.clientY })
  }

  // Two fingers

  touched(event) {
    this.pinch = event.touches.length === 2 ? { apart: apart(event.touches), zoom: this.asked } : null
  }

  pinched(event) {
    if (!this.pinch || event.touches.length !== 2 || !this.zooms) return

    if (event.cancelable) event.preventDefault()
    const [one, other] = event.touches
    const between = { x: (one.clientX + other.clientX) / 2, y: (one.clientY + other.clientY) / 2 }
    this.zoomSoon(this.pinch.zoom * apart(event.touches) / this.pinch.apart, between)
  }

  released(event) {
    if (event.touches.length < 2) this.pinch = null
  }

  // Safari says a pinch on a trackpad this way, and no wheel. It says it of two fingers
  // on a screen as well, which are counted above: there it is only kept from zooming
  // the whole page.
  gestured(event) {
    if (!this.zooms) return

    event.preventDefault()
    if (this.pinch) return
    if (event.type === "gesturestart") this.gesture = this.asked
    else if (this.gesture) this.zoomSoon(this.gesture * event.scale, { x: event.clientX, y: event.clientY })
  }

  // Dragging a picture with the mouse. Not text: there a drag picks what to copy.

  held(event) {
    if (event.pointerType !== "mouse" || event.button !== 0 || this.zoom === 1) return
    if (!this.hasPictureTarget || !this.hasScrollerTarget || !this.scrollerTarget.contains(event.target)) return

    const { scrollLeft: left, scrollTop: top } = this.scrollerTarget
    this.grip = { x: event.clientX, y: event.clientY, left, top }
    this.element.toggleAttribute("data-zoom-dragging", true)
    window.addEventListener("pointermove", this.dragged)
    window.addEventListener("pointerup", this.dropped)
    window.addEventListener("pointercancel", this.dropped)
    // or the browser picks the picture up to drop it somewhere
    event.preventDefault()
  }

  dragged(event) {
    const scale = zoomOf(this.scrollerTarget)
    this.scrollerTarget.scrollLeft = this.grip.left - (event.clientX - this.grip.x) / scale
    this.scrollerTarget.scrollTop = this.grip.top - (event.clientY - this.grip.y) / scale
  }

  dropped() {
    this.grip = null
    this.element.removeAttribute("data-zoom-dragging")
    window.removeEventListener("pointermove", this.dragged)
    window.removeEventListener("pointerup", this.dropped)
    window.removeEventListener("pointercancel", this.dropped)
  }

  // Plus, minus and zero, while the keyboard is with the file: in its dialog, in its
  // tile, or on its page with no dialog over it. With Ctrl or Cmd they are the browser's.

  keyed(event) {
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey || !this.zooms) return
    if (!this.keyboardIsHere(event.target)) return

    const turn = { "+": "zoomIn", "=": "zoomIn", "-": "zoomOut", "_": "zoomOut", "0": "fit" }[event.key]
    if (!turn) return

    event.preventDefault()
    this[turn]()
  }

  keyboardIsHere(at) {
    if (!(at instanceof Element) || at.closest("input, textarea, select, [contenteditable], rhino-editor")) return false

    const dialog = this.element.closest("dialog")
    if (at.closest("dialog") !== dialog) return false
    if (dialog) return true

    const tile = tileOf(this.element)
    return tile ? tile.contains(at) : true
  }
}

function apart(touches) {
  return Math.hypot(touches[0].clientX - touches[1].clientX, touches[0].clientY - touches[1].clientY) || 1
}

function middleOf(element) {
  const box = element.getBoundingClientRect()
  return { x: box.left + box.width / 2, y: box.top + box.height / 2 }
}
