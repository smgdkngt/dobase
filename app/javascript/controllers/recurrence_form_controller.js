import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "optionsSection",
    "intervalUnit",
    "weeklyOptions",
    "monthlyOptions",
    "endCountField",
    "endUntilField"
  ]

  static values = { frequency: { type: String, default: "none" } }

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

  toggleDayButton(event) {
    const label = event.target.closest("label")
    if (event.target.checked) {
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
