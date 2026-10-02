import { Controller } from "@hotwired/stimulus"
import { apiPatch } from "services/api"
import { applyTheme } from "services/theme"

// The typeface and theme pickers of the profile (profiles/_appearance). A pick is put
// on at once, right where you are: the form by itself would send you to the profile
// page, out of the dialog it is usually in, and out of the workspace around that.
export default class extends Controller {
  static targets = ["option"]

  async pick(event) {
    const picked = event.submitter
    if (!picked?.name) return

    event.preventDefault()
    const theme = await apiPatch("/appearance", { [picked.name]: picked.value || null })
    if (!theme) return

    applyTheme(theme)
    for (const option of this.optionTargets) {
      const on = option === picked
      option.classList.toggle("theme-option-selected", on)
      option.setAttribute("aria-pressed", on)
    }
  }
}
