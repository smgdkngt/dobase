import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator", "status", "button"]
  static values = {
    url: String,
    syncing: Boolean
  }

  connect() {
    if (this.syncingValue) {
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  sync() {
    // Start syncing UI immediately
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.remove("bg-success", "bg-error")
      this.indicatorTarget.classList.add("bg-warning")
    }
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Syncing..."
    }
    if (this.hasButtonTarget) {
      const icon = this.buttonTarget.querySelector("svg")
      if (icon) icon.classList.add("animate-spin")
    }
    this.startPolling()
  }

  // One timer at a time: a second click on "Sync now" (or a click during a sync the
  // page already polls for) must not leave an earlier timer running that nothing clears
  startPolling() {
    this.stopPolling()
    this.pollInterval = setInterval(() => this.checkStatus(), 1000)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  async checkStatus() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()

      if (data.status === "synced" || data.status === "error") {
        this.stopPolling()
        Turbo.visit(window.location.href, { action: "replace" })
      }
    } catch (error) {
      console.error("Error checking sync status:", error)
    }
  }
}
