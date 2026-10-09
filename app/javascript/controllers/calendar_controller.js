import { Controller } from "@hotwired/stimulus"
import { pageAddress, visitPage, tileOf, zoomOf } from "services/tile"

export default class extends Controller {
  static targets = ["grid", "hours", "today", "eventModal", "eventDetailDialog", "newEventDialog", "newEventModal", "weekInput", "startTimeInput", "endTimeInput"]
  static values = {
    toolId: Number,
    weekStart: String
  }

  connect() {
    this.setupScrollPreservation()
    this.restoreScrollPosition()

    // An event opens by itself with ?event=ID in the address
    const eventId = pageAddress(this.element).searchParams.get("event")
    if (eventId) this._openEvent(eventId)
  }

  disconnect() {
    this.teardownScrollPreservation()
  }

  // Before the page is drawn again: the window's page, or the tile's when the
  // calendar is a tile in the workspace's own page
  setupScrollPreservation() {
    this.beforeRenderHandler = this.saveScrollPosition.bind(this)
    this.drawnIn = tileOf(this.element)
    ;(this.drawnIn || document).addEventListener(this.drawnIn ? "turbo:before-frame-render" : "turbo:before-render", this.beforeRenderHandler)
  }

  teardownScrollPreservation() {
    (this.drawnIn || document).removeEventListener(this.drawnIn ? "turbo:before-frame-render" : "turbo:before-render", this.beforeRenderHandler)
  }

  saveScrollPosition() {
    if (this.hasGridTarget) {
      sessionStorage.setItem("calendar-scroll-top", this.gridTarget.scrollTop.toString())
    }
  }

  restoreScrollPosition() {
    const top = sessionStorage.getItem("calendar-scroll-top")

    if (top && this.hasGridTarget) {
      sessionStorage.removeItem("calendar-scroll-top")

      requestAnimationFrame(() => {
        this.gridTarget.scrollTop = parseInt(top, 10)
      })
    } else {
      // No saved position - scroll to current time
      this.scrollToCurrentTime()
    }
    this.scrollToToday()
  }

  // On a narrow screen the week is wider than the grid and opened on Monday, with today
  // somewhere off to the right. This week opens with today's column first, right after
  // the hours; another week has no today and starts at its Monday. Where all seven days
  // fit there is nothing to scroll.
  scrollToToday() {
    if (!this.hasGridTarget || !this.hasTodayTarget || !this.hasHoursTarget) return

    requestAnimationFrame(() => {
      const zoom = zoomOf(this.gridTarget)
      const afterHours = this.gridTarget.getBoundingClientRect().left / zoom + this.hoursTarget.offsetWidth
      this.gridTarget.scrollLeft += this.todayTarget.getBoundingClientRect().left / zoom - afterHours
    })
  }

  // Opens the week at the hour the grid asks for (the one before now, in the
  // viewer's time zone), measured from the grid itself: the header above it
  // sticks, and is taller with an all-day row
  scrollToCurrentTime() {
    if (!this.hasGridTarget) return

    requestAnimationFrame(() => {
      const body = this.gridTarget.querySelector("[data-scroll-hour]")
      const slot = body?.querySelector(`[data-hour="${body.dataset.scrollHour}"]`)
      if (!slot) return

      this.gridTarget.scrollTop = (slot.getBoundingClientRect().top - body.getBoundingClientRect().top) / zoomOf(this.gridTarget)
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

    const eventId = event.currentTarget.dataset.eventId
    if (eventId) this._openEvent(eventId)
  }

  _openEvent(eventId) {
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
          // The keyboard on what closes it, not on Delete, which comes first
          this.eventModalTarget.querySelector("[autofocus], [data-action~='click->modal#close'], button, a[href]")?.focus()
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

  // A date input, not a week input: Safari and Firefox have no week picker
  openWeekPicker() {
    if (!this.hasWeekInputTarget) return

    try {
      this.weekInputTarget.showPicker()
    } catch {
      this.weekInputTarget.focus()
      this.weekInputTarget.click()
    }
  }

  jumpToWeek(event) {
    if (!event.target.value) return

    this.navigateToWeek(this.getMonday(this.parseDate(event.target.value)))
  }

  // The arrow keys go from event to event (arrow_keys_controller.js); past the first
  // or the last one of the week they go on to the week before or after
  pastTheWeek(event) {
    // The page's own arrow keys, not the menu's or the notifications'
    if (!event.target.contains(this.element) || ![ "left", "right" ].includes(event.detail.side)) return

    event.preventDefault()
    event.detail.side === "left" ? this.previousWeek() : this.nextWeek()
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

  // A Turbo visit, not a page load: loading the page anew would end a call that is
  // going on in the corner (the browser asks "Leave site?" first)
  navigateToWeek(date) {
    const weekStart = this.formatDate(date)
    const week = `/tools/${this.toolIdValue}/calendar?week_start=${weekStart}`
    tileOf(this.element) ? visitPage(this.element, week) : Turbo.visit(week)
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
