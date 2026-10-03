import { Controller } from "@hotwired/stimulus"
import { apiPatch } from "services/api"
import { applyTheme, scheme } from "services/theme"

// The typeface and theme pickers of the profile (profiles/_appearance). A pick is put
// on at once, right where you are: the form by itself would send you to the profile
// page, out of the dialog it is usually in, and out of the workspace around that.
//
// The theme can be one, or one for when the system is light and one for when it is
// dark. Then the grid picks for one of the two at a time (the slot): the one this
// browser is in to begin with, so what you pick is what you see.
export default class extends Controller {
  static targets = ["option", "mode", "slots", "slot", "scheme"]

  connect() {
    if (this.following) this.show(scheme())
  }

  get following() {
    return this.hasSlotsTarget && !this.slotsTarget.hidden
  }

  async pick(event) {
    const picked = event.submitter
    if (!picked?.name) return

    event.preventDefault()
    const change = { [picked.name]: picked.value || null }
    // Going to two themes or back to one keeps what this browser shows right now
    if (picked.name === "follow_system") Object.assign(change, { follow_system: picked.value === "1", scheme: scheme() })
    if (picked.name === "theme" && this.following) change.scheme = this.slot

    const appearance = await apiPatch("/appearance", change)
    if (!appearance) return

    applyTheme(appearance)
    picked.name === "typeface" ? this.mark((option) => option === picked) : this.draw(appearance)
  }

  // The other of the two themes: the grid shows which one that is, and picks for it
  showSlot(event) {
    this.show(event.currentTarget.dataset.scheme)
  }

  show(slot) {
    this.slot = slot
    for (const button of this.slotTargets) {
      press(button, button.dataset.scheme === slot, "theme-slot-on")
      if (button.dataset.scheme === slot) this.markTheme(button.dataset.theme)
    }
    if (this.hasSchemeTarget) this.schemeTarget.value = slot
  }

  // What the server says is on now, in every part of the picker
  draw(appearance) {
    const following = Boolean(appearance.follows_system)
    for (const mode of this.modeTargets) press(mode, (mode.value === "1") === following, "theme-mode-on")
    if (this.hasSlotsTarget) this.slotsTarget.hidden = !following
    if (this.hasSchemeTarget) this.schemeTarget.disabled = !following

    if (!following) return this.markTheme(appearance.name || "", appearance.custom)

    for (const button of this.slotTargets) {
      const worn = appearance[button.dataset.scheme]
      button.dataset.theme = worn?.name || ""
      button.querySelector("[data-slot-label]").textContent = worn?.label || ""
    }
    this.show(this.slot || scheme())
  }

  // A palette of one's own has a button that can't be pressed, beside the built-in ones
  markTheme(name, custom = false) {
    this.mark((option) => option.name === "theme" && option.value === name && option.disabled === Boolean(custom))
  }

  mark(on) {
    for (const option of this.optionTargets) press(option, on(option), "theme-option-selected")
  }
}

function press(button, on, className) {
  button.classList.toggle(className, on)
  button.setAttribute("aria-pressed", on)
}
