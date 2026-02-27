import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { apiPatch } from "services/api"

let dragInProgress = false

export default class extends Controller {
  static values = {
    group: String,
    handle: String,
    url: String,
    paramName: { type: String, default: "ids" },
    animation: { type: Number, default: 150 }
  }

  connect() {
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
      opts.filter = "[data-controller='sortable']"
      opts.preventOnFilter = false
    }

    this.sortable = new Sortable(this.element, opts)
  }

  disconnect() {
    if (dragInProgress) return
    this.sortable?.destroy()
  }

  onEnd(evt) {
    dragInProgress = false

    if (evt.from !== evt.to) {
      this.dispatch("move", {
        detail: {
          itemId: evt.item.dataset.sortId,
          fromId: evt.from.dataset.groupId,
          toId: evt.to.dataset.groupId
        }
      })
    }

    // Save the order of the target container
    this._saveContainerOrder(evt.to)

    // Also save the source container if item moved between containers
    if (evt.from !== evt.to) {
      this._saveContainerOrder(evt.from)
    }
  }

  _saveContainerOrder(container) {
    const ctrl = this.application.getControllerForElementAndIdentifier(container, "sortable")
    if (!ctrl?.hasUrlValue) return

    const ids = Array.from(container.querySelectorAll(":scope > [data-sort-id]"))
      .map(el => el.dataset.sortId)
    apiPatch(ctrl.urlValue, { [ctrl.paramNameValue]: ids })
  }
}
