import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "eventModal", "eventDetailDialog", "newEventDialog", "newEventModal", "weekInput", "startTimeInput", "endTimeInput"]
  static values = {
    toolId: Number,
    weekStart: String
  }

  connect() {
    this.setupScrollPreservation()
    this.restoreScrollPosition()
  }

  disconnect() {
    this.teardownScrollPreservation()
  }

  setupScrollPreservation() {
    this.beforeRenderHandler = this.saveScrollPosition.bind(this)
    document.addEventListener("turbo:before-render", this.beforeRenderHandler)
  }

  teardownScrollPreservation() {
    document.removeEventListener("turbo:before-render", this.beforeRenderHandler)
  }

  saveScrollPosition() {
    if (this.hasGridTarget) {
      sessionStorage.setItem("calendar-scroll-top", this.gridTarget.scrollTop.toString())
      sessionStorage.setItem("calendar-scroll-left", this.gridTarget.scrollLeft.toString())
    }
  }

  restoreScrollPosition() {
    const top = sessionStorage.getItem("calendar-scroll-top")
    const left = sessionStorage.getItem("calendar-scroll-left")

    if (top && this.hasGridTarget) {
      sessionStorage.removeItem("calendar-scroll-top")
      sessionStorage.removeItem("calendar-scroll-left")

      requestAnimationFrame(() => {
        this.gridTarget.scrollTop = parseInt(top, 10)
        if (left) this.gridTarget.scrollLeft = parseInt(left, 10)
      })
    } else {
      // No saved position - scroll to current time
      this.scrollToCurrentTime()
    }
  }

  scrollToCurrentTime() {
    if (!this.hasGridTarget) return

    requestAnimationFrame(() => {
      const now = new Date()
      const hour = now.getHours()
      const hourHeight = 60 // Each hour slot is 60px
      const headerHeight = 52 // Week header height

      // Scroll to current hour minus 2 hours for context
      const targetHour = Math.max(0, hour - 2)
      const scrollTop = headerHeight + (targetHour * hourHeight)

      this.gridTarget.scrollTop = scrollTop
    })
  }

  newEvent(event) {
    // If called from a click event, prevent default
    if (event && event.preventDefault) {
      event.preventDefault()
    }

    if (this.hasNewEventDialogTarget) this.newEventDialogTarget.showModal()
  }

  createAtSlot(event) {
    // Only respond to clicks on the slot itself, not on events
    if (event.target.closest("[data-event-id]")) return

    const slot = event.currentTarget
    const column = slot.closest("[data-date]")
    const date = column.dataset.date
    const hour = parseInt(slot.dataset.hour, 10)

    // Calculate minutes based on click position within the slot (round to 30-min)
    const rect = slot.getBoundingClientRect()
    const y = event.clientY - rect.top
    const percentageY = y / rect.height
    const minute = percentageY < 0.5 ? 0 : 30

    // Set the start time in the new event form
    // Parse date parts to avoid timezone issues with ISO date strings
    const [year, month, day] = date.split("-").map(Number)
    const startTime = new Date(year, month - 1, day, hour, minute, 0, 0)

    // Set end time (1 hour later)
    const endTime = new Date(startTime)
    endTime.setHours(startTime.getHours() + 1, minute, 0, 0)

    if (this.hasStartTimeInputTarget && this.hasEndTimeInputTarget) {
      this.startTimeInputTarget.value = this.formatDateTimeLocal(startTime)
      this.endTimeInputTarget.value = this.formatDateTimeLocal(endTime)
      // So the repeat options follow the new start
      this.startTimeInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    // Open the new event modal
    this.newEvent()
  }

  showEvent(event) {
    event.preventDefault()
    event.stopPropagation()

    const eventBlock = event.currentTarget
    const eventId = eventBlock.dataset.eventId

    if (!eventId) return

    // Fetch event details and show in modal
    const url = `/tools/${this.toolIdValue}/calendar/events/${eventId}`

    // Open immediately with a skeleton so the dialog's entrance isn't spent
    // staring at a blank sheet — content swaps in once the fetch resolves.
    if (this.hasEventModalTarget) {
      this.eventModalTarget.innerHTML = this._eventSkeletonHTML()
    }
    if (this.hasEventDetailDialogTarget) this.eventDetailDialogTarget.showModal()

    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => response.text())
      .then(html => {
        if (this.hasEventModalTarget) {
          this.eventModalTarget.innerHTML = html
          this.eventModalTarget.querySelector("[autofocus], button, a[href]")?.focus()
        }
      })
      .catch(error => {
        console.error("Error loading event:", error)
      })
  }

  _eventSkeletonHTML() {
    return `
      <div class="flex flex-col gap-3">
        <div class="skeleton h-5 w-2/3"></div>
        <div class="skeleton h-4 w-1/3"></div>
        <div class="skeleton h-4 w-1/2"></div>
        <div class="skeleton h-16 w-full mt-2"></div>
      </div>
    `
  }

  closeModal() {
    // Close any open modals
    const modals = document.querySelectorAll("dialog[open]")
    modals.forEach(modal => modal.close())
  }

  goToToday() {
    const today = new Date()
    const monday = this.getMonday(today)
    this.navigateToWeek(monday)
  }

  openWeekPicker() {
    if (this.hasWeekInputTarget) {
      this.weekInputTarget.showPicker()
    }
  }

  jumpToWeek(event) {
    const weekValue = event.target.value // Format: "2024-W07"
    if (!weekValue) return

    const [year, week] = weekValue.split("-W")
    const date = this.getDateOfISOWeek(parseInt(week), parseInt(year))
    this.navigateToWeek(date)
  }

  getDateOfISOWeek(week, year) {
    const jan4 = new Date(year, 0, 4)
    const dayOfWeek = jan4.getDay() || 7
    const monday = new Date(jan4)
    monday.setDate(jan4.getDate() - dayOfWeek + 1 + (week - 1) * 7)
    return monday
  }

  previousWeek() {
    const currentWeekStart = this.parseDate(this.weekStartValue)
    currentWeekStart.setDate(currentWeekStart.getDate() - 7)
    this.navigateToWeek(currentWeekStart)
  }

  nextWeek() {
    const currentWeekStart = this.parseDate(this.weekStartValue)
    currentWeekStart.setDate(currentWeekStart.getDate() + 7)
    this.navigateToWeek(currentWeekStart)
  }

  // new Date("2026-09-14") is midnight UTC, which is the day before west of UTC
  parseDate(value) {
    const [year, month, day] = value.split("-").map(Number)
    return new Date(year, month - 1, day)
  }

  navigateToWeek(date) {
    const weekStart = this.formatDate(date)
    window.location.href = `/tools/${this.toolIdValue}/calendar?week_start=${weekStart}`
  }

  getMonday(date) {
    const d = new Date(date)
    const day = d.getDay()
    const diff = d.getDate() - day + (day === 0 ? -6 : 1) // Adjust when day is Sunday
    return new Date(d.setDate(diff))
  }

  formatDate(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  formatDateTimeLocal(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const minutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }
}
