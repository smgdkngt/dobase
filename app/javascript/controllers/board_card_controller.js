import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

// Controls the card detail modal content loaded dynamically into card-detail-modal.
// Registered as "board-card" so it scopes cleanly to each loaded card.
export default class extends Controller {
  static values = { cardId: String, toolId: String }
  static targets = [
    "titleDisplay", "titleInput",
    "descriptionDisplay", "descriptionEdit",
    "dueDateLabel", "dueDateInput",
    "colorDot", "colorLabel",
    "assigneeLabel"
  ]

  // ── Title editing ──

  editTitle() {
    this.titleDisplayTarget.classList.add("hidden")
    this.titleInputTarget.classList.remove("hidden")
    this.titleInputTarget.focus()
    this.titleInputTarget.select()
  }

  saveTitle() {
    const value = this.titleInputTarget.value.trim()
    if (value && value !== this.titleDisplayTarget.textContent.trim()) {
      this.titleDisplayTarget.textContent = value
      this._save({ title: value })
    }
    this.titleInputTarget.classList.add("hidden")
    this.titleDisplayTarget.classList.remove("hidden")
  }

  titleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.titleInputTarget.blur()
    }
    if (event.key === "Escape") {
      this.titleInputTarget.value = this.titleDisplayTarget.textContent.trim()
      this.titleInputTarget.blur()
    }
  }

  // ── Description ──

  editDescription() {
    if (this.hasDescriptionDisplayTarget && this.hasDescriptionEditTarget) {
      this.descriptionDisplayTarget.classList.add("hidden")
      this.descriptionEditTarget.classList.remove("hidden")
    }
  }

  cancelDescription() {
    if (this.hasDescriptionDisplayTarget && this.hasDescriptionEditTarget) {
      this.descriptionEditTarget.classList.add("hidden")
      this.descriptionDisplayTarget.classList.remove("hidden")
    }
  }

  // ── Color ──

  setColor(event) {
    const color = event.currentTarget.dataset.color
    const hex = event.currentTarget.dataset.colorHex

    if (this.hasColorLabelTarget) {
      this.colorLabelTarget.textContent = color ? color.charAt(0).toUpperCase() + color.slice(1) : "No label"
    }

    if (this.hasColorDotTarget) {
      this.colorDotTarget.style.cssText = hex
        ? `background-color: ${hex};`
        : "background-color: transparent; border: 1px dashed var(--color-border);"
    }

    this._save({ color: color || null })
  }

  // ── Due date ──

  setDueDate(event) {
    const value = event.target.value
    this._save({ due_date: value || null })

    if (this.hasDueDateLabelTarget) {
      if (value) {
        const [year, month, day] = value.split("-").map(Number)
        const date = new Date(year, month - 1, day)
        this.dueDateLabelTarget.textContent = date.toLocaleDateString("en-US", {
          month: "short", day: "numeric", year: "numeric"
        })
      } else {
        this.dueDateLabelTarget.textContent = "No due date"
      }
    }
  }

  // ── Assignee ──

  setAssignee(event) {
    const userId = event.currentTarget.dataset.userId
    const userName = event.currentTarget.dataset.userName || "Unassigned"

    if (this.hasAssigneeLabelTarget) {
      this.assigneeLabelTarget.textContent = userName
    }

    this._save({ assigned_user_id: userId || null })
  }

  // ── Attachment upload ──

  submitAttachment(event) {
    event.target.form.requestSubmit()
    event.target.value = ""
  }

  // ── Private ──

  _save(data) {
    api(`/tools/${this.toolIdValue}/board/cards/${this.cardIdValue}`, "PATCH", { card: data })
  }
}
