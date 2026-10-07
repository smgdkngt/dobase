import { Controller } from "@hotwired/stimulus"
import { typing } from "services/typing"

// Keyboard shortcuts are handled declaratively via data-hotkey attributes
// in the view. This controller only provides the behavior methods that
// those hotkey-triggered buttons call.

export default class extends Controller {
  static targets = ["list", "item", "reader"]

  connect() {
    this._onFrameLoad = this._handleFrameLoad.bind(this)
    const frame = this._frame
    if (frame) frame.addEventListener("turbo:frame-load", this._onFrameLoad)
    this._onKey = (event) => this._keyed(event)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    const frame = this._frame
    if (frame) frame.removeEventListener("turbo:frame-load", this._onFrameLoad)
    document.removeEventListener("keydown", this._onKey)
  }

  // The arrow keys go through the conversations as they go through any tool's items
  // (arrow_keys_controller.js; each conversation's link is one), on to the buttons
  // above the list and into the message beside it. What is mail's own:
  //
  // - With the message beside the list, getting to a conversation opens it, as j and
  //   k do. In a narrow window (a tile, a phone with a keyboard) the list and the
  //   message take turns: the arrows move through the list, and Enter or the right
  //   arrow opens.
  // - The space bar turns the page of the message, Escape lets go of the conversation.
  _keyed(event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (typing(event) || document.querySelector("dialog[open], :popover-open")) return

    if (event.key === "Escape" && (this.selectedItem || !this._listShows)) {
      event.preventDefault()
      return this._listShows ? this.deselect() : this.backToList()
    }
    if (event.key === " " && this._messageShows && !event.target.matches?.("a[href], button, input, summary, [role='button']")) {
      event.preventDefault()
      const scroller = this._scroller
      scroller?.scrollBy({ top: (event.shiftKey ? -1 : 1) * scroller.clientHeight * 0.85 })
    }
  }

  // The arrow keys got to a conversation
  went(event) {
    const item = event.target.closest?.("[data-mail-keyboard-target='item']")
    if (!item || item.classList.contains("selected")) return
    if (this._messageShows) return this.navigateToItem(item)

    this.items.forEach((other) => other.classList.remove("selected"))
    item.classList.add("selected")
  }

  // Nothing further on a side. To the right of the list, where the message doesn't
  // show beside it: the conversation opens. To the left of a message that has the
  // window to itself: back to the list.
  edge(event) {
    const { side } = event.detail
    if (side === "right" && this._listShows && !this._messageShows && this.selectedItem) {
      event.preventDefault()
      this.openSelected()
    } else if (side === "left" && !this._listShows) {
      event.preventDefault()
      this.backToList()
    }
  }

  get items() {
    return this.hasListTarget
      ? [...this.listTarget.querySelectorAll("[data-mail-keyboard-target='item']")]
      : this.itemTargets
  }

  get selectedItem() {
    return this.items.find(item => item.classList.contains("selected"))
  }

  get selectedIndex() {
    return this.selectedItem ? this.items.indexOf(this.selectedItem) : -1
  }

  selectNext() {
    const items = this.items
    if (!items.length) return
    const next = (this.selectedIndex + 1) % items.length
    this.navigateToItem(items[next])
  }

  selectPrevious() {
    const items = this.items
    if (!items.length) return
    const prev = this.selectedIndex > 0 ? this.selectedIndex - 1 : items.length - 1
    this.navigateToItem(items[prev])
  }

  // The buttons on an open conversation: the next one in the list, or the one before.
  // Not round to the other end, as the keys go: at the last one there is no next.
  stepNext() {
    this.navigateToItem(this.items[this.selectedIndex + 1])
  }

  stepPrevious() {
    if (this.selectedIndex > 0) this.navigateToItem(this.items[this.selectedIndex - 1])
  }

  // What scrolls the message that shows: the reader, or what it lies in
  get _scroller() {
    const reader = this.readerTargets.find((target) => target.getClientRects().length > 0)
    for (let element = reader; element && element !== this.element.parentElement; element = element.parentElement) {
      if (element.scrollHeight > element.clientHeight + 1 && /auto|scroll/.test(getComputedStyle(element).overflowY)) return element
    }
    return reader || null
  }

  // Only where the list and the message take turns: side by side there is nothing to
  // go back to. The keyboard goes back to the conversation it came from.
  backToList() {
    if (this._listShows) return

    this.element.classList.remove("mail-detail-open")
    this.selectedItem?.querySelector("a[href]")?.focus()
  }

  get _listShows() {
    return this.hasListTarget && this.listTarget.getClientRects().length > 0
  }

  get _messageShows() {
    const frame = this._frame
    return Boolean(frame) && frame.getClientRects().length > 0
  }

  // The frame a conversation is read in (MailsHelper#mail_frame_id): this mailbox's,
  // of however many are on the page
  get _frame() {
    return this.element.querySelector("turbo-frame[data-mail-frame]")
  }

  navigateToItem(item) {
    if (!item) return
    // The keyboard goes along, so the arrow keys go on from here
    item.querySelector("a[href]")?.focus({ preventScroll: true })
    // Update visual selection immediately
    this.items.forEach(i => i.classList.remove("selected"))
    item.classList.add("selected")
    // The global prefers-reduced-motion rule can't reach a behavior passed in
    // JavaScript, so ask for the preference here instead.
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    item.scrollIntoView({ block: "nearest", behavior: reduceMotion ? "auto" : "smooth" })

    // Mark as read visually (the server marks it read, but the list doesn't re-render)
    this._markItemRead(item)

    const link = item.querySelector("a[href]")
    if (link) link.click()
  }

  selectItem(event) {
    const item = event.currentTarget.closest("[data-mail-keyboard-target='item']")
    if (!item) return
    this.items.forEach(i => i.classList.remove("selected"))
    item.classList.add("selected")
    this._markItemRead(item)
  }

  openSelected() {
    const selected = this.selectedItem
    if (!selected) return
    const link = selected.querySelector("a[href]")
    if (link) link.click()
  }

  deselect() {
    this.items.forEach(item => item.classList.remove("selected"))
    document.activeElement?.blur()
  }

  // Toggle mobile detail view when mail-content frame loads
  _handleFrameLoad() {
    this.element.classList.add("mail-detail-open")
    // Where the message takes the list's place, the keyboard doesn't stay on a
    // conversation that is out of sight: the arrows read the message from here
    if (!this._listShows && this.listTarget.contains(document.activeElement)) document.activeElement.blur()
  }

  // Remove unread indicators from a conversation item (dot, bold from/subject)
  _markItemRead(item) {
    const dot = item.querySelector(".bg-accent.rounded-full.w-2.h-2")
    if (dot) dot.remove()

    item.querySelectorAll(".font-semibold, .font-medium").forEach(el => {
      el.classList.remove("font-semibold", "font-medium")
    })
  }
}
