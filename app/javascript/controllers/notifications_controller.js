import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["badge", "trigger", "popover", "list", "markAllRead"]
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
    this.unreadCountValue += 1
    this.updateBadge()

    // If the popover is open, prepend the notification to the list
    if (this.hasListTarget) {
      const item = this.buildNotificationHTML(data)
      this.listTarget.insertAdjacentHTML("afterbegin", item)
    }
  }

  togglePopover() {
    // The popover API handles show/hide. We just need to reload the frame
    // when opened to get fresh data.
    const frame = this.popoverTarget.querySelector("turbo-frame")
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
  }

  buildNotificationHTML(data) {
    const timeAgo = "just now"
    const unreadClass = "bg-accent-light/30"
    const fontClass = "font-medium"

    return `
      <a href="${data.url}"
         data-turbo-frame="_top"
         class="flex items-start gap-3 px-4 py-3 hover:bg-background-secondary transition-colors border-b border-border-light ${unreadClass}"
         data-action="click->notifications#markAsRead"
         data-notification-id="${data.id}">
        <div class="flex-shrink-0 mt-0.5 text-text-secondary">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>
          </svg>
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm text-text-primary leading-snug ${fontClass}">${data.message}</p>
          <p class="text-xs text-text-tertiary mt-0.5">${timeAgo}</p>
        </div>
        <div class="flex-shrink-0 mt-1.5">
          <span class="block w-2 h-2 rounded-full bg-accent"></span>
        </div>
      </a>
    `
  }
}
