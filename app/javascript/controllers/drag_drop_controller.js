import { Controller } from "@hotwired/stimulus"
import { apiPost } from "services/api"
import { showFlash } from "services/flash"
import { play } from "services/sound"
import { visitPage } from "services/tile"

// Dragging from one place in Dobase to another (Dropped, DragDropHelper). It lives on
// <body> and knows no tool: an item says what it is (`data-drag-sgid`, its kind, its
// tool, its title and address), a place says what it takes and where to send it
// (`data-drop-url`), and the server makes of it what that place makes: a card, a todo,
// a chat message, a file, a draft. A place can also send the item to one of the item's
// own addresses instead (`data-drop-action`: a mail dropped on a folder is moved there).
//
// The drag also carries the item as a link (text/uri-list, text/html, text/plain), so
// dropping it in a text field, an editor (inside a place too) or another program gives
// its title and address.
// What a page drags within itself (a card to another column, a file into a folder) is
// still that page's own, and goes on as before: a place takes nothing from its own tool.
const TYPE = "application/x-dobase"

export default class extends Controller {
  connect() {
    this.started = this.started.bind(this)
    this.over = this.over.bind(this)
    this.dropped = this.dropped.bind(this)
    this.ended = this.ended.bind(this)
    document.addEventListener("dragstart", this.started)
    document.addEventListener("dragover", this.over)
    document.addEventListener("drop", this.dropped)
    document.addEventListener("dragend", this.ended)
  }

  disconnect() {
    document.removeEventListener("dragstart", this.started)
    document.removeEventListener("dragover", this.over)
    document.removeEventListener("drop", this.dropped)
    document.removeEventListener("dragend", this.ended)
  }

  // After the page's own handlers (SortableJS, the files'), so the link is what
  // another program gets as text
  started(event) {
    const source = event.target.closest?.("[data-drag-sgid]")
    const transfer = event.dataTransfer
    if (!source || !transfer) return

    const { dragSgid: sgid, dragKind: kind, dragTool: tool, dragTitle: title, dragUrl: url } = source.dataset
    const actions = Object.fromEntries(Object.entries(source.dataset)
      .filter(([ key ]) => /^drag.+Url$/.test(key) && key !== "dragUrl")
      .map(([ key, value ]) => [ key.replace(/^drag(.+)Url$/, "$1").toLowerCase(), value ]))

    transfer.setData(TYPE, JSON.stringify({ sgid, actions }))
    // What is being dragged is only known by the names of its types until it is dropped
    transfer.setData(`${TYPE}-kind-${kind}`, "")
    transfer.setData(`${TYPE}-tool-${tool}`, "")
    Object.keys(actions).forEach((action) => transfer.setData(`${TYPE}-can-${action}`, ""))
    transfer.setData("text/uri-list", url)
    transfer.setData("text/plain", url)
    transfer.setData("text/html", `<a href="${escape(url)}">${escape(title)}</a>`)
    transfer.effectAllowed = "all"
    this.source = source
  }

  over(event) {
    this.springOpen(event)
    const place = this.placeFor(event)
    this.mark(place)
    if (!place) return

    event.preventDefault()
    event.dataTransfer.dropEffect = place.dataset.dropAction ? "move" : "copy"
  }

  async dropped(event) {
    const place = this.placeFor(event)
    this.mark(null)
    if (!place) return

    event.preventDefault()
    const { sgid, actions } = JSON.parse(event.dataTransfer.getData(TYPE) || "{}")
    const action = place.dataset.dropAction
    const url = action ? actions?.[action] : place.dataset.dropUrl
    if (!url) return

    const body = action ? JSON.parse(place.dataset.dropParams || "{}") : { dropped: sgid }
    const answer = await apiPost(url, body)
    if (!answer) {
      play("error")
      showFlash("That can't go there")
      return
    }

    play("drop")
    if (place.dataset.dropOpen && answer.id) {
      Turbo.visit(place.dataset.dropOpen.replace(":id", answer.id))
      return
    }
    showFlash(place.dataset.dropDone || "Done", "notice")
    // The page dropped on and the one dragged from show it (the change was this page's own request)
    for (const element of new Set([ place, this.source ])) {
      if (element?.isConnected && element.closest(".tile-page, main")) visitPage(element)
    }
  }

  ended() {
    this.mark(null)
    this.source = null
    clearTimeout(this.opening)
    this.opener = null
  }

  // A button that opens a menu of places (the mail's folders), held over for a moment
  // with something dragged, opens it, as a folder does in a file manager
  springOpen(event) {
    const opener = [ ...(event.dataTransfer?.types || []) ].includes(TYPE) ? event.target.closest?.("[data-drop-opens]") : null
    if (opener === this.opener) return

    clearTimeout(this.opening)
    this.opener = opener
    if (!opener) return

    this.opening = setTimeout(() => {
      const menu = opener.popoverTargetElement
      if (menu && !menu.matches(":popover-open")) menu.showPopover()
    }, 500)
  }

  // The place under the pointer that takes what is being dragged: by its kind, from
  // another tool; or, for one of its own addresses, from its own tool
  placeFor(event) {
    const types = [ ...(event.dataTransfer?.types || []) ]
    if (!types.includes(TYPE)) return null

    // In a field or an editor (a chat's message box, a document) it is the link it carries
    if (event.target.closest?.("input, textarea, [contenteditable=true], rhino-editor")) return null

    const place = event.target.closest?.("[data-drop-url], [data-drop-action]")
    if (!place) return null

    const fromHere = types.includes(`${TYPE}-tool-${place.dataset.dropTool}`)
    if (place.dataset.dropAction) return fromHere && types.includes(`${TYPE}-can-${place.dataset.dropAction}`) ? place : null

    const kinds = (place.dataset.dropAccepts || "").split(" ")
    return !fromHere && kinds.some((kind) => types.includes(`${TYPE}-kind-${kind}`)) ? place : null
  }

  mark(place) {
    if (place === this.marked) return

    this.marked?.removeAttribute("data-drop-over")
    place?.setAttribute("data-drop-over", "")
    this.marked = place
  }
}

function escape(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" })[character])
}
