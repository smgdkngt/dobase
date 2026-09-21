import { Controller } from "@hotwired/stimulus"
import { apiPost, apiDelete } from "services/api"

// Emoji on a chat message. The row arrives over the chat's broadcast, the
// same for everyone, so which emoji are yours is marked here, each time the
// row is drawn. A click puts yours on or takes it off; the new row comes back
// over the broadcast.
export default class extends Controller {
  static targets = ["row", "pill"]
  static values = { url: String }

  pillTargetConnected(pill) {
    pill.setAttribute("aria-pressed", this._isMine(pill) ? "true" : "false")
  }

  toggle(event) {
    const pill = event.currentTarget
    this._send(pill.dataset.emoji, !this._isMine(pill))
  }

  // From the picker: an emoji already yours stays on, rather than coming off
  pick(event) {
    const emoji = event.currentTarget.dataset.emoji
    event.currentTarget.closest("[popover]")?.hidePopover()
    const pill = this.pillTargets.find((candidate) => candidate.dataset.emoji === emoji)
    if (pill && this._isMine(pill)) return
    this._send(emoji, true)
  }

  _send(emoji, on) {
    if (on) {
      apiPost(this.urlValue, { emoji })
    } else {
      apiDelete(`${this.urlValue}/${encodeURIComponent(emoji)}`)
    }
  }

  _isMine(pill) {
    const userId = this.element.closest("[data-chat-user-id-value]")?.dataset.chatUserIdValue
    return Boolean(userId) && pill.dataset.userIds.split(" ").includes(userId)
  }
}
