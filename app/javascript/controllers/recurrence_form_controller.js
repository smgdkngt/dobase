import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "optionsSection",
    "intervalUnit",
    "weeklyOptions",
    "monthlyOptions",
    "endCountField",
    "endUntilField",
    "day",
    "weekdayLabel"
  ]

  // followStart: the weekly day and the monthly weekday follow the start until a day is picked
  static values = { frequency: { type: String, default: "none" }, followStart: Boolean }

  connect() {
    this.updateVisibility()
  }

  frequencyChanged(event) {
    this.frequencyValue = event.target.value
    this.updateVisibility()
  }

  endTypeChanged(event) {
    this.updateEndFields(event.target.value)
  }

  startChanged(event) {
    const [year, month, day] = event.target.value.split("T")[0].split("-").map(Number)
    if (!year || !month || !day) return

    const start = new Date(year, month - 1, day)
    const ordinals = ["1st", "2nd", "3rd", "4th", "5th"]
    const weekday = start.toLocaleDateString("en-US", { weekday: "long" })
    if (this.hasWeekdayLabelTarget) {
      this.weekdayLabelTarget.textContent = `The ${ordinals[Math.floor((day - 1) / 7)]} ${weekday}`
    }

    if (!this.followStartValue) return
    const code = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][start.getDay()]
    this.dayTargets.forEach((checkbox) => {
      checkbox.checked = checkbox.value === code
      this.styleDay(checkbox)
    })
  }

  toggleDayButton(event) {
    this.followStartValue = false
    this.styleDay(event.target)
  }

  styleDay(checkbox) {
    const label = checkbox.closest("label")
    if (checkbox.checked) {
      label.classList.add("bg-accent", "text-white", "border-accent")
      label.classList.remove("border-border", "text-text-secondary", "hover:border-accent/50")
    } else {
      label.classList.remove("bg-accent", "text-white", "border-accent")
      label.classList.add("border-border", "text-text-secondary", "hover:border-accent/50")
    }
  }

  updateVisibility() {
    const freq = this.frequencyValue
    const isNone = !freq || freq === "none"

    if (this.hasOptionsSectionTarget) {
      this.optionsSectionTarget.classList.toggle("hidden", isNone)
    }

    if (this.hasIntervalUnitTarget) {
      const units = { daily: "day(s)", weekly: "week(s)", monthly: "month(s)", yearly: "year(s)" }
      this.intervalUnitTarget.textContent = units[freq] || ""
    }

    if (this.hasWeeklyOptionsTarget) {
      this.weeklyOptionsTarget.classList.toggle("hidden", freq !== "weekly")
    }

    if (this.hasMonthlyOptionsTarget) {
      this.monthlyOptionsTarget.classList.toggle("hidden", freq !== "monthly")
    }
  }

  updateEndFields(endType) {
    if (this.hasEndCountFieldTarget) {
      this.endCountFieldTarget.classList.toggle("hidden", endType !== "count")
    }
    if (this.hasEndUntilFieldTarget) {
      this.endUntilFieldTarget.classList.toggle("hidden", endType !== "until")
    }
  }
}
