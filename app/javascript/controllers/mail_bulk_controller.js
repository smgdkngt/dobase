import { Controller } from "@hotwired/stimulus"

// Manages bulk selection in the mail list: select-all, per-row checkboxes,
// showing/hiding the bulk-action toolbar, and submitting move-to-folder.
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "actions"]

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.updateActions()
  }

  toggle(event) {
    // Keep ticking the box from triggering the row's navigation.
    event.stopPropagation()
    this.updateActions()
  }

  updateActions() {
    const anyChecked = this.checkboxTargets.some(cb => cb.checked)
    this.actionsTarget.classList.toggle("hidden", !anyChecked)
  }

  moveToFolder(event) {
    this.setHidden("action_type", "move_to_folder")
    this.setHidden("target_folder", event.currentTarget.dataset.folder)
    this.element.requestSubmit()
  }

  setHidden(name, value) {
    let input = this.element.querySelector(`input[type="hidden"][name="${name}"]`)
    if (!input) {
      input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      this.element.appendChild(input)
    }
    input.value = value
  }
}
