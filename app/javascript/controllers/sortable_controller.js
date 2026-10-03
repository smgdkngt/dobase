import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { apiPatch } from "services/api"
import { play } from "services/sound"

let dragInProgress = false

export default class extends Controller {
  static values = {
    group: String,
    handle: String,
    url: String,
    paramName: { type: String, default: "ids" },
    animation: { type: Number, default: 150 },
    enabled: { type: Boolean, default: true }
  }

  connect() {
    if (this.enabledValue) this._createSortable()
  }

  disconnect() {
    if (dragInProgress) return
    this.sortable?.destroy()
    this.sortable = null
  }

  enabledValueChanged(enabled) {
    if (enabled) {
      this._createSortable()
    } else {
      this.sortable?.destroy()
      this.sortable = null
    }
  }

  _createSortable() {
    if (this.sortable) return
    // Skip nested sortables during drag (prevents interference)
    if (dragInProgress && this.element.closest("[data-sort-id]")) return

    const opts = {
      animation: this.animationValue,
      draggable: "[data-sort-id]",
      dataIdAttr: "data-sort-id",
      fallbackOnBody: true,
      swapThreshold: 0.65,
      onStart: () => { dragInProgress = true },
      onEnd: this.onEnd.bind(this)
    }
    if (this.hasGroupValue) opts.group = this.groupValue
    if (this.hasHandleValue) {
      opts.handle = this.handleValue
    } else {
      // The whole item is the handle, so on a touch screen a drag would start under every
      // finger that lands on one, and a swipe would move a card instead of scrolling the
      // page. A finger has to rest on the item first; a mouse drags right away.
      opts.delay = 200
      opts.delayOnTouchOnly = true
      opts.touchStartThreshold = 5
      // With pointer events, Sortable misses the end of a swipe the browser took over for
      // scrolling (pointercancel) and ignores the next touch; touch events end properly.
      opts.supportPointer = false
    }

    this.sortable = new Sortable(this.element, opts)
  }

  async onEnd(evt) {
    // Defer resetting dragInProgress until after MutationObserver callbacks
    // have been processed. SortableJS DOM cleanup (ghost removal, class changes)
    // triggers Stimulus disconnect/connect via MutationObserver. If we reset
    // dragInProgress synchronously, those callbacks see it as false and
    // incorrectly destroy card sortable instances inside moved columns.
    requestAnimationFrame(() => { dragInProgress = false })
    if (evt.from !== evt.to || evt.oldIndex !== evt.newIndex) play("drop")

    if (evt.from !== evt.to) {
      // Whoever hears the move may have to tell the server first (the sidebar moves the
      // tool to its new group). The order is only saved once that is done: saved earlier,
      // it would not include an item the server doesn't know to be there yet.
      const pending = []
      this.dispatch("move", {
        detail: {
          itemId: evt.item.dataset.sortId,
          fromId: evt.from.dataset.groupId,
          toId: evt.to.dataset.groupId,
          waitUntil: (promise) => pending.push(promise)
        }
      })
      await Promise.all(pending)
    }

    // Save the order of the target container
    this._saveContainerOrder(evt.to)

    // Also save the source container if item moved between containers
    if (evt.from !== evt.to) {
      this._saveContainerOrder(evt.from)
    }
  }

  // What a drag does, for the keyboard (arrow_keys_controller.js): the item goes one
  // place up or down among its siblings, or across to the list of the same group on
  // that side, at the height it was. False when there is nowhere to go.
  moveWithKeys(item, side) {
    if (!this.enabledValue) return false

    const siblings = Array.from(this.element.querySelectorAll(":scope > [data-sort-id]"))
    const index = siblings.indexOf(item)
    // Not one of this list's own (a done todo, kept apart further down)
    if (index < 0) return false

    if (side === "up" || side === "down") {
      const other = siblings[index + (side === "up" ? -1 : 1)]
      if (!other) return false

      side === "up" ? other.before(item) : other.after(item)
      this._saveContainerOrder(this.element)
      return true
    }

    const to = this._listBeside(side)
    if (!to) return false

    const from = this.element
    const there = Array.from(to.querySelectorAll(":scope > [data-sort-id]"))
    there[index] ? there[index].before(item) : there.length ? there.at(-1).after(item) : to.prepend(item)
    this._moved(item, from, to)
    return true
  }

  // The nearest list of the same group to the left or the right of this one
  _listBeside(side) {
    if (!this.hasGroupValue) return null

    const here = this.element.getBoundingClientRect()
    return Array.from(document.querySelectorAll(`[data-controller~='sortable'][data-sortable-group-value='${this.groupValue}']`))
      .filter((list) => list !== this.element && list.getClientRects().length > 0)
      .map((list) => ({ list, rect: list.getBoundingClientRect() }))
      .filter(({ rect }) => side === "left" ? rect.left < here.left : rect.left > here.left)
      .sort((a, b) => Math.abs(a.rect.left - here.left) - Math.abs(b.rect.left - here.left))[0]?.list || null
  }

  async _moved(item, from, to) {
    const pending = []
    this.dispatch("move", {
      detail: { itemId: item.dataset.sortId, fromId: from.dataset.groupId, toId: to.dataset.groupId, waitUntil: (promise) => pending.push(promise) }
    })
    await Promise.all(pending)

    this._saveContainerOrder(to)
    this._saveContainerOrder(from)
  }

  _saveContainerOrder(container) {
    const ctrl = this.application.getControllerForElementAndIdentifier(container, "sortable")
    if (!ctrl?.hasUrlValue) return

    const ids = Array.from(container.querySelectorAll(":scope > [data-sort-id]"))
      .map(el => el.dataset.sortId)
    apiPatch(ctrl.urlValue, { [ctrl.paramNameValue]: ids })
  }
}
