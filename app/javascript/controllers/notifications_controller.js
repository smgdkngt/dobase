import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["badge", "badgeStatus", "trigger", "popover", "list", "markAllRead"]
  static values = { userId: Number, unreadCount: Number }

  connect() {
    this.updateBadge()
    this.setupActionCable()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  setupActionCable() {
    this.channel = consumer.subscriptions.create(
      { channel: "NotificationChannel" },
      {
        received: (data) => this.handleNotification(data)
      }
    )
  }

  handleNotification(data) {
    // Live presence ping from the Room tool (see Tools::Rooms::ActivitiesController) —
    // not a real notification, so it skips the bell/badge/list entirely and just
    // toggles the same in-call indicator the room controller uses for itself.
    if (data.type === "room_activity") {
      this.updateInCallIndicator(data.tool_id, data.active)
      return
    }

    this.unreadCountValue += 1
    this.updateBadge()

    // Show activity dot on sidebar tool item
    if (data.tool_id) {
      const toolItem = document.querySelector(`[data-tool-id="${data.tool_id}"]`)
      if (toolItem && !toolItem.classList.contains("sidebar-item-active")) {
        const link = toolItem.querySelector("[data-sidebar-tool-link]") || toolItem
        link.setAttribute("data-unread", "")
      }
    }

    // If the popover is open, prepend the notification to the list
    if (this.hasListTarget) {
      this.listTarget.prepend(this.buildNotificationElement(data))
    }
  }

  updateInCallIndicator(toolId, active) {
    const toolItem = document.querySelector(`[data-tool-id="${toolId}"]`)
    if (!toolItem) return
    if (active) {
      toolItem.setAttribute("data-in-call", "")
    } else {
      toolItem.removeAttribute("data-in-call")
    }
  }

  togglePopover() {
    // The popover API handles show/hide. We just need to reload the frame
    // when opened to get fresh data. The mobile bottom bar's trigger is a
    // separate instance of this controller that only wraps the trigger
    // button — the popover with the frame lives in the sidebar, outside
    // this element's scope on mobile — so fall back to the frame's id.
    const frame = this.hasPopoverTarget
      ? this.popoverTarget.querySelector("turbo-frame")
      : document.getElementById("notifications")
    if (frame) {
      frame.reload()
    }
  }

  markAsRead(event) {
    const notificationId = event.currentTarget.dataset.notificationId
    if (!notificationId) return

    fetch(`/notifications/${notificationId}/read`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "application/json"
      }
    })

    // Optimistically update the UI
    const dot = event.currentTarget.querySelector(".bg-accent")
    if (dot) dot.remove()
    event.currentTarget.classList.remove("bg-accent-light/30")
    event.currentTarget.querySelector("p")?.classList.remove("font-medium")

    if (this.unreadCountValue > 0) {
      this.unreadCountValue -= 1
      this.updateBadge()
    }
  }

  markAllRead(event) {
    // Let the form submit normally, then update the UI
    this.unreadCountValue = 0
    this.updateBadge()

    // Reload the frame after a short delay to reflect changes
    setTimeout(() => {
      const frame = this.popoverTarget.querySelector("turbo-frame")
      if (frame) frame.reload()
    }, 300)
  }

  clearAll() {
    fetch("/notification_clears", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "application/json"
      }
    }).then(() => {
      this.unreadCountValue = 0
      this.updateBadge()
      const frame = this.popoverTarget.querySelector("turbo-frame")
      if (frame) frame.reload()
    })
  }

  updateBadge() {
    if (!this.hasBadgeTarget) return

    if (this.unreadCountValue > 0) {
      this.badgeTarget.textContent = this.unreadCountValue > 99 ? "99+" : this.unreadCountValue
      this.badgeTarget.classList.remove("hidden")
    } else {
      this.badgeTarget.classList.add("hidden")
    }

    // The badge itself is aria-hidden (a bare number reads as nonsense); the
    // count lives in a visually hidden status region next to it instead.
    if (this.hasBadgeStatusTarget) {
      const count = this.unreadCountValue
      this.badgeStatusTarget.textContent =
        count === 0
          ? "No unread notifications"
          : `${count} unread notification${count === 1 ? "" : "s"}`
    }
  }

  // Built with DOM APIs rather than a template string: data.message comes
  // from another user's action (e.g. a chat message or file name) and must
  // never be parsed as markup, even though CSP already stops it from
  // executing as a script.
  buildNotificationElement(data) {
    const link = document.createElement("a")
    link.href = data.url
    link.dataset.turboFrame = "_top"
    link.className = "flex items-start gap-3 px-4 py-3 hover:bg-background-tertiary transition-colors border-b border-border-light bg-accent-light/30"
    link.dataset.action = "click->notifications#markAsRead"
    link.dataset.notificationId = data.id

    const iconWrap = document.createElement("div")
    iconWrap.className = "flex-shrink-0 mt-0.5 text-text-secondary"
    iconWrap.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>'

    const textWrap = document.createElement("div")
    textWrap.className = "flex-1 min-w-0"

    const message = document.createElement("p")
    message.className = "text-sm text-text-primary leading-snug font-medium"
    message.textContent = data.message

    const timeAgo = document.createElement("p")
    timeAgo.className = "text-xs text-text-tertiary mt-0.5"
    timeAgo.textContent = "just now"

    textWrap.append(message, timeAgo)

    const dotWrap = document.createElement("div")
    dotWrap.className = "flex-shrink-0 mt-1.5"
    const dot = document.createElement("span")
    dot.className = "block w-2 h-2 rounded-full bg-accent"
    dotWrap.appendChild(dot)

    link.append(iconWrap, textWrap, dotWrap)
    return link
  }
}
