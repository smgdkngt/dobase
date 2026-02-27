import { Controller } from "@hotwired/stimulus"

// Calendar Invite Form Controller
// Dynamically updates the form action when user selects a different calendar
export default class extends Controller {
  static targets = ["calendarSelect"]
  static values = {
    calendarMap: Object,  // Maps calendar_id => tool_id
    inviteId: Number
  }

  updateFormAction() {
    const calendarId = parseInt(this.calendarSelectTarget.value)
    const toolId = this.calendarMapValue[calendarId]

    if (toolId) {
      // Update form action to point to the correct calendar tool
      this.element.action = `/tools/${toolId}/calendar/invites`
    }
  }
}
