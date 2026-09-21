import { Controller } from "@hotwired/stimulus"
import { workspacePresence } from "services/workspace_presence"

// Small faces beside a tool in the sidebar for everyone who has it open right
// now, so you can see where your colleagues are without opening each tool.
const MAX_FACES = 3

export default class extends Controller {
  static targets = ["slot"]
  static values = { userId: Number }

  connect() {
    this.presence = workspacePresence(this.userIdValue)
    this.stopListening = this.presence.subscribe(() => this.render())
    this.render()
  }

  disconnect() {
    this.stopListening?.()
  }

  // A slot can arrive later, when a tool is added to the sidebar without a reload
  slotTargetConnected(slot) {
    if (this.presence) this.renderSlot(slot)
  }

  render() {
    this.slotTargets.forEach((slot) => this.renderSlot(slot))
  }

  renderSlot(slot) {
    const people = this.presence.peopleIn(slot.dataset.toolId)
    slot.replaceChildren(...people.slice(0, MAX_FACES).map((person) => this.faceFor(person)))

    if (people.length > MAX_FACES) {
      const more = document.createElement("span")
      more.className = "sidebar-presence-more"
      more.textContent = `+${people.length - MAX_FACES}`
      slot.appendChild(more)
    }

    slot.hidden = people.length === 0
    slot.title = people.map((person) => person.name).join(", ")
    slot.setAttribute("aria-label", people.length ? `Here now: ${slot.title}` : "")
  }

  faceFor(person) {
    const face = document.createElement("span")
    face.className = "sidebar-presence-face avatar"

    if (person.avatar_url) {
      const image = document.createElement("img")
      image.src = person.avatar_url
      image.alt = ""
      image.className = "w-full h-full object-cover"
      face.appendChild(image)
    } else {
      face.textContent = person.initials
    }

    return face
  }
}
