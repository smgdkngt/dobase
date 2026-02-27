import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  select(event) {
    // Remove active state from all cards
    this.cardTargets.forEach(card => {
      card.classList.remove("border-accent", "ring-2", "ring-accent/20", "bg-accent/5")
      card.classList.add("border-border-light")
    })

    // Add active state to selected card
    const card = event.target.closest("[data-tool-type-select-target='card']")
    if (card) {
      card.classList.remove("border-border-light")
      card.classList.add("border-accent", "ring-2", "ring-accent/20", "bg-accent/5")
    }
  }
}
