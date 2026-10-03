import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { applyTheme, refreshTheme } from "services/theme"
import { play } from "services/sound"

export default class extends Controller {
  static targets = ["badge", "badgeStatus", "trigger", "popover", "list", "markAllRead", "desktopOffer"]
  static values = { userId: Number, unreadCount: Number, unreadMailCount: Number, appName: String }

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

    // A theme was picked: on the profile page, on another device, by the CLI
    if (data.type === "theme") {
      // Without one in the message there is a theme for light and one for dark, and
      // each page asks for its own
      data.theme ? applyTheme(data.theme) : refreshTheme()
      return
    }

    // Unread mail changed: new mail came in, or something was read somewhere
    if (data.type === "unread_mail") {
      // More than there was: mail came in
      if (data.count > this.unreadMailCountValue) play("mail", { once: `mail-${data.count}` })
      this.unreadMailCountValue = data.count
      return
    }

    // Something was read somewhere (opening a card reads what it was about)
    if (data.type === "unread_count") {
      this.unreadCountValue = data.count
      this.updateBadge()
      if (this.hasListTarget) this.reloadList()
      return
    }

    this.unreadCountValue += 1
    this.updateBadge()
    // What happens in the tool you are looking at is heard there, if at all (a chat
    // message has its own sound); anything else is heard here
    if (document.hidden || !this.lookingAt(data.tool_id)) play("notify", { once: `notification-${data.id}` })

    // Show activity dot on sidebar tool item
    if (data.tool_id) {
      const toolItem = document.querySelector(`[data-tool-id="${data.tool_id}"]`)
      if (toolItem && !toolItem.classList.contains("sidebar-item-active")) {
        const link = toolItem.querySelector("[data-sidebar-tool-link]") || toolItem
        link.setAttribute("data-unread", "")
      }
    }

    // An open list is drawn again by the server, which knows who said what and
    // folds a busy chat into one line
    if (this.hasListTarget) this.reloadList()

    this.showOnDesktop(data)
  }

  // On the tool's own page, or in the workspace with a tile of it in sight (which
  // workspace_controller.js marks on the tool's link in the menu)
  lookingAt(toolId) {
    if (!toolId) return false

    return new RegExp(`^/tools/${toolId}(/|$)`).test(location.pathname) ||
      Boolean(document.querySelector(`[data-tool-id="${toolId}"] [data-sidebar-tool-link][data-in-sight]`))
  }

  reloadList() {
    const frame = this.hasPopoverTarget ? this.popoverTarget.querySelector("turbo-frame") : null
    frame?.reload()
  }

  // An OS notification, only while this page is in a background tab and only
  // once the person has said yes. Several open tabs show it once: the same tag
  // replaces rather than stacks.
  showOnDesktop(data) {
    if (!("Notification" in window) || Notification.permission !== "granted" || !document.hidden) return

    const notification = new Notification(this.appNameValue || "Dobase", {
      body: data.message,
      tag: `notification-${data.id}`,
      icon: "/icon-192.png"
    })
    notification.onclick = () => {
      window.focus()
      if (data.url) Turbo.visit(data.url)
      notification.close()
    }
  }

  // The offer only makes sense while the browser hasn't been asked
  desktopOfferTargetConnected(offer) {
    offer.hidden = !("Notification" in window) || Notification.permission !== "default"
  }

  async enableDesktop() {
    await Notification.requestPermission()
    this.desktopOfferTargets.forEach((offer) => this.desktopOfferTargetConnected(offer))
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

    // The keyboard goes along (the bell that was pressed may be another one's: the
    // bars at the top and the bottom each have one for the same list)
    const popover = document.getElementById("sidebar-notifications")
    requestAnimationFrame(() => { if (popover?.matches(":popover-open")) popover.focus({ preventScroll: true }) })
  }

  // One line can stand for several notifications (a busy chat); all of them are read
  markAsRead(event) {
    const row = event.currentTarget
    const ids = (row.dataset.notificationIds || "").split(",").filter(Boolean)
    if (ids.length === 0 || row.dataset.unread !== "true") return

    ids.forEach((id) => {
      fetch(`/notifications/${id}/read`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        }
      })
    })

    // Optimistically update the UI
    row.dataset.unread = "false"
    row.classList.remove("notification-row-unread")
    row.querySelector(".notification-dot")?.remove()

    this.unreadCountValue = Math.max(0, this.unreadCountValue - ids.length)
    this.updateBadge()
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

  // A Turbo morph refresh brings the server's counts along
  unreadCountValueChanged() {
    this.updateAppBadge()
  }

  unreadMailCountValueChanged() {
    this.updateAppBadge()
  }

  // The installed app's icon counts unread mail and notifications together, like a mail
  // program's dock icon (the Badging API; the browser ignores it outside an installed app)
  updateAppBadge() {
    if (!("setAppBadge" in navigator)) return

    const count = this.unreadCountValue + this.unreadMailCountValue
    const badged = count > 0 ? navigator.setAppBadge(count) : navigator.clearAppBadge()
    badged.catch(() => {})
  }

  updateBadge() {
    this.updateAppBadge()
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
}
