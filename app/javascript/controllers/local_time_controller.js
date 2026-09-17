import { Controller } from "@hotwired/stimulus"

// Redraws a <time> in the viewer's time zone, which the page names in <meta name="time-zone">.
// The server writes it in the zone of whoever's request rendered it, which for a broadcast
// chat message is the sender's.
export default class extends Controller {
  static values = { period: { type: Boolean, default: true } }

  connect() {
    const date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(date)) return

    const timeZone = document.querySelector('meta[name="time-zone"]')?.content || undefined
    const parts = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone }).formatToParts(date)
    this.element.textContent = parts
      .filter(part => this.periodValue || !["dayPeriod", "literal"].includes(part.type) || part.value === ":")
      .map(part => part.value)
      .join("")
      .replace(/\s/g, " ") // Intl puts a narrow space before AM/PM
  }
}
