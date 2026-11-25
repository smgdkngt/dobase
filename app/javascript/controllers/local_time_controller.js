import { Controller } from "@hotwired/stimulus"
import { _, intlLocale } from "services/i18n"

const DAY = 24 * 60 * 60 * 1000

// Redraws a <time> in the viewer's time zone, which the page names in <meta name="time-zone">.
// The server writes it in the zone of whoever's request rendered it, which for a broadcast
// chat message is the sender's.
export default class extends Controller {
  static values = { period: { type: Boolean, default: true }, day: { type: Boolean, default: false } }

  connect() {
    const date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(date)) return

    const timeZone = document.querySelector('meta[name="time-zone"]')?.content || undefined
    const parts = new Intl.DateTimeFormat(intlLocale(), { hour: "numeric", minute: "2-digit", timeZone }).formatToParts(date)
    const time = parts
      .filter(part => this.periodValue || !["dayPeriod", "literal"].includes(part.type) || part.value === ":")
      .map(part => part.value)
      .join("")
      .replace(/\s/g, " ") // Intl puts a narrow space before AM/PM
    this.element.textContent = this.dayValue ? this.withDay(date, time, timeZone) : time
  }

  withDay(date, time, timeZone) {
    const elapsed = Date.now() - date.getTime()
    if (elapsed < DAY) return time
    if (elapsed < 2 * DAY) return _("Yesterday, %{time}", { time })

    const year = (moment) => new Intl.DateTimeFormat(intlLocale(), { year: "numeric", timeZone }).format(moment)
    const withYear = year(date) !== year(new Date()) ? { year: "numeric" } : {}
    const day = new Intl.DateTimeFormat(intlLocale(), { month: "short", day: "numeric", timeZone, ...withYear }).format(date)
    return _("%{date}, %{time}", { date: day, time })
  }
}
