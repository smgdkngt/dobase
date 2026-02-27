import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

export default class extends Controller {
  static values = { itemId: String, toolId: String }
  static targets = [
    "titleDisplay", "titleInput",
    "descriptionDisplay", "descriptionEdit",
    "dueDateInput",
    "assigneeLabel"
  ]

  // ── Completion toggle ──

  async toggleCompletion(event) {
    const checked = event.currentTarget.checked
    const method = checked ? "POST" : "DELETE"
    const url = `/tools/${this.toolIdValue}/todo/items/${this.itemIdValue}/completion`
    await api(url, method)
  }

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

  // ── Due date ──

  setDueDate(event) {
    const value = event.target.value
    this._save({ due_date: value || null })
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

  // ── Attachment ──

  submitAttachment(event) {
    event.target.closest("form").requestSubmit()
  }

  // ── Private ──

  _save(data) {
    api(`/tools/${this.toolIdValue}/todo/items/${this.itemIdValue}`, "PATCH", { item: data })
  }
}
