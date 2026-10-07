import { Controller } from "@hotwired/stimulus"
import { visitPage } from "services/tile"
import { pageInUse } from "services/page_in_use"

const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content

export default class extends Controller {
  static targets = ["indicator"]
  static values = {
    interval: { type: Number, default: 60 },
    url: String
  }

  connect() {
    this.syncing = false
    this.handleVisibility = () => document.hidden ? this.stopTimer() : this.startTimer()
    document.addEventListener("visibilitychange", this.handleVisibility)
    this.startTimer()
  }

  disconnect() {
    this.stopTimer()
    document.removeEventListener("visibilitychange", this.handleVisibility)
  }

  // Saving the mail settings refreshes the page with a morph, which changes the
  // interval without connecting the controller again
  intervalValueChanged() {
    this.stopTimer()
    this.startTimer()
  }

  // An interval of 0 means auto-refresh is disabled
  startTimer() {
    if (this.timer || this.intervalValue <= 0) return
    this.timer = setInterval(() => this.sync(), this.intervalValue * 1000)
  }

  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  // The refresh morphs the page back to what the server renders: it closes dialogs and
  // menus, unticks the bulk checkboxes and empties a field that is being typed in. So it
  // waits for a later turn while one of those is going on.
  get busy() {
    return pageInUse() || Boolean(this.element.querySelector("[data-mail-bulk-target='checkbox']:checked"))
  }

  async sync() {
    if (this.syncing || !this.urlValue || this.busy) return
    this.syncing = true
    if (this.hasIndicatorTarget) this.indicatorTarget.classList.remove("hidden")

    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (res.ok) {
        // Use Turbo Drive visit to refresh the page — data-turbo-permanent
        // preserves the persistent room PiP during the visit
        visitPage(this.element)
      }
    } catch (e) {
      console.error("Mail sync failed:", e)
    } finally {
      this.syncing = false
      if (this.hasIndicatorTarget) this.indicatorTarget.classList.add("hidden")
    }
  }
}
