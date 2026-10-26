import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"
import { showFlash } from "services/flash"
import { play } from "services/sound"
import { gesture, done, DOING_DISTANCE } from "services/swipe"
import { visitPage } from "services/tile"

// On a phone a conversation in the list is archived by swiping it to the left, as in a
// phone's own mail app. The row goes at once; when the server refuses, it comes back.
// Only rows that say where archiving them goes (data-archive-url) can be swiped.
export default class extends Controller {
  connect() {
    this._start = this.start.bind(this)
    this._move = this.move.bind(this)
    this._end = this.end.bind(this)
    this._click = this.swallowClick.bind(this)
    this.element.addEventListener("touchstart", this._start, { passive: true })
    this.element.addEventListener("touchmove", this._move, { passive: true })
    this.element.addEventListener("touchend", this._end)
    this.element.addEventListener("touchcancel", this._end)
    this.element.addEventListener("click", this._click, true)
  }

  disconnect() {
    clearTimeout(this.catchingUp)
    this.element.removeEventListener("touchstart", this._start)
    this.element.removeEventListener("touchmove", this._move)
    this.element.removeEventListener("touchend", this._end)
    this.element.removeEventListener("touchcancel", this._end)
    this.element.removeEventListener("click", this._click, true)
  }

  start(event) {
    const row = event.target.closest("[data-archive-url]")
    if (!row || event.touches.length !== 1 || !matchMedia("(max-width: 639px)").matches) return
    const touch = event.touches[0]
    this.swipe = { row, x: touch.clientX, y: touch.clientY, time: event.timeStamp, distance: 0, kind: null }
  }

  move(event) {
    const swipe = this.swipe
    if (!swipe) return
    const touch = event.touches[0]
    const sideways = swipe.x - touch.clientX
    swipe.kind ||= gesture(sideways, touch.clientY - swipe.y)
    if (swipe.kind !== "swipe") {
      if (swipe.kind === "scroll") this.swipe = null
      return
    }
    swipe.distance = Math.max(0, sideways)
    swipe.row.dataset.swiping = ""
    swipe.row.style.setProperty("--swipe", `${-swipe.distance}px`)
    swipe.row.toggleAttribute("data-swipe-armed", swipe.distance >= DOING_DISTANCE)
  }

  end(event) {
    const swipe = this.swipe
    this.swipe = null
    if (!swipe || swipe.kind !== "swipe") return
    // The tap that ends a swipe opens nothing
    this.swallowNextClick = true
    setTimeout(() => { this.swallowNextClick = false }, 400)

    const { row } = swipe
    delete row.dataset.swiping
    row.removeAttribute("data-swipe-armed")
    if (event.type === "touchend" && done(swipe.distance, event.timeStamp - swipe.time)) {
      this.archive(row)
    } else {
      row.style.removeProperty("--swipe")
    }
  }

  // The folder's count and the page around the list follow once nothing is being
  // swiped any more: a few rows swiped one after another are one drawing
  catchUp() {
    clearTimeout(this.catchingUp)
    this.catchingUp = setTimeout(() => {
      if (this.swipe || this.element.querySelector("[data-swiped-away]:not([data-gone])")) return this.catchUp()
      visitPage(this.element)
    }, 1200)
  }

  swallowClick(event) {
    if (!this.swallowNextClick) return
    this.swallowNextClick = false
    event.preventDefault()
    event.stopPropagation()
  }

  async archive(row) {
    row.dataset.swipedAway = ""
    play("tuck")
    const result = await api(row.dataset.archiveUrl, "POST")
    if (result) {
      // From its height to none, so the rows under it close up instead of jumping
      row.style.height = `${row.offsetHeight}px`
      row.getBoundingClientRect()
      row.dataset.gone = ""
      row.style.height = ""
      setTimeout(() => row.remove(), 450)
      this.catchUp()
    } else {
      delete row.dataset.swipedAway
      row.style.removeProperty("--swipe")
      showFlash("The mail couldn't be archived.", "alert")
    }
  }
}
