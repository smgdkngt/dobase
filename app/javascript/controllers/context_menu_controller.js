import { Controller } from "@hotwired/stimulus"
import { zoomOf } from "services/tile"
import { showFlash } from "services/flash"

// What a right click on an item offers (components/context_menu). It lives on <body>
// and knows no tool: an item says `data-context-menu` and carries its menu as a
// <template> of links and buttons the server drew, which this shows at the pointer.
// Also from the keyboard (Shift+F10, the menu key) for the item that has it.
//
// The menu is put in the item's own page (a tile, or <main>), so what is pressed in
// it counts as pressed there: a tile of the workspace goes on to the right page.
// Shift with the right click, or a click in a field or on selected text, is the
// browser's own menu.
export default class extends Controller {
  connect() {
    this.opened = this.opened.bind(this)
    this.keyed = this.keyed.bind(this)
    this.pressed = this.pressed.bind(this)
    this.released = this.released.bind(this)
    document.addEventListener("contextmenu", this.opened)
    document.addEventListener("keydown", this.keyed)
    document.addEventListener("pointerdown", this.pressed, true)
    document.addEventListener("pointerup", this.released, true)
    document.addEventListener("pointercancel", this.released, true)
  }

  disconnect() {
    document.removeEventListener("contextmenu", this.opened)
    document.removeEventListener("keydown", this.keyed)
    document.removeEventListener("pointerdown", this.pressed, true)
    document.removeEventListener("pointerup", this.released, true)
    document.removeEventListener("pointercancel", this.released, true)
    this.close()
  }

  // On a Mac and on Linux the menu is asked for as the button goes down, and on a
  // touch screen while the finger is still on it. A popover shown then is closed by
  // the button or finger coming up (it was pressed outside any popover), so the menu
  // waits for that.
  pressed() {
    this.down = true
  }

  released() {
    this.down = false
    const waiting = this.waiting
    this.waiting = null
    if (waiting) setTimeout(waiting)
  }

  opened(event) {
    if (event.defaultPrevented || event.shiftKey) return

    const item = itemOf(event.target)
    if (!item || event.target.closest("input:not([type=checkbox]):not([type=radio]), textarea, select, [contenteditable=true], rhino-editor")) return
    if (hasSelectedText(item)) return

    event.preventDefault()
    // A long press on a touch screen has no pointer to put the menu at: under the finger
    const show = () => this.open(item, event.clientX, event.clientY)
    this.down ? this.waiting = show : show()
  }

  keyed(event) {
    if (!(event.key === "ContextMenu" || (event.key === "F10" && event.shiftKey))) return

    const item = itemOf(document.activeElement)
    if (!item) return

    event.preventDefault()
    const rect = item.getBoundingClientRect()
    this.open(item, rect.left + 16, rect.top + Math.min(rect.height, 32), { keyboard: true })
  }

  open(item, x, y, { keyboard = false } = {}) {
    this.close()
    const template = templateOf(item)
    if (!template) return

    const menu = document.createElement("div")
    menu.className = "popover-menu context-menu"
    menu.setAttribute("popover", "auto")
    menu.setAttribute("role", "menu")
    menu.setAttribute("aria-label", template.getAttribute("aria-label") || "Actions")
    // Not the server's: the page isn't drawn again under it while it is open
    menu.setAttribute("data-live-busy", "")
    menu.append(template.content.cloneNode(true))
    withoutWhatIsHidden(menu, item)
    menu.addEventListener("click", (event) => this.chose(event))
    menu.addEventListener("toggle", (event) => { if (event.newState === "closed") this.closed(menu) })

    ;(item.closest(".tile-page") || item.closest("main") || document.body).append(menu)
    menu.showPopover()
    place(menu, x, y)

    this.menu = menu
    this.item = item
    item.setAttribute("data-context-menu-open", "")
    if (keyboard) menu.querySelector("[role=menuitem]")?.focus()
  }

  close() {
    if (this.menu?.matches(":popover-open")) this.menu.hidePopover()
    else if (this.menu) this.closed(this.menu)
  }

  copy(event) {
    const text = event.currentTarget.dataset.copy
    navigator.clipboard?.writeText(text).then(() => showFlash("Copied", "notice"), () => showFlash("Couldn't copy"))
  }

  // What was chosen goes first (Turbo's own click listener on the document follows
  // this one), then the menu goes
  chose(event) {
    const entry = event.target.closest("[role=menuitem]")
    if (!entry) return

    const pressed = buttonFor(entry, this.item)
    setTimeout(() => {
      this.close()
      pressed?.click()
    })
  }

  closed(menu) {
    menu.remove()
    if (this.menu !== menu) return

    this.item?.removeAttribute("data-context-menu-open")
    this.menu = this.item = null
  }
}

function itemOf(element) {
  return element?.closest?.("[data-context-menu]")
}

// The item's own menu, not that of an item inside it
function templateOf(item) {
  return [ ...item.querySelectorAll("template[data-context-menu-items]") ].find((template) => itemOf(template) === item)
}

// An entry that says `data-context-menu-press` presses the item's own button that
// says that as `data-context-menu-action` (a chat message's Reply, Edit, Delete)
function buttonFor(entry, item) {
  const action = entry.dataset.contextMenuPress
  return action && item?.querySelector(`[data-context-menu-action="${action}"]`)
}

// What the item doesn't offer just now (your own message's Edit, not someone else's)
// isn't in its menu, nor a line with nothing on one side of it
function withoutWhatIsHidden(menu, item) {
  menu.querySelectorAll("[data-context-menu-press]").forEach((entry) => {
    const button = buttonFor(entry, item)
    if (!button || button.closest(".hidden, [hidden]")) entry.remove()
  })
  menu.querySelectorAll("[role=separator]").forEach((line) => {
    const before = line.previousElementSibling, after = line.nextElementSibling
    if (!before || !after || after.matches("[role=separator]")) line.remove()
  })
}

function hasSelectedText(item) {
  const selection = window.getSelection()
  return selection && !selection.isCollapsed && item.contains(selection.anchorNode)
}

// At the pointer, inside the window. Where the pointer is on the screen is measured
// as drawn, where the menu goes as laid out: a tile is drawn smaller than that.
function place(menu, x, y) {
  const rect = menu.getBoundingClientRect()
  const left = Math.max(4, Math.min(x, window.innerWidth - rect.width - 4))
  const top = y + rect.height > window.innerHeight ? Math.max(4, y - rect.height) : y
  const zoom = zoomOf(menu)
  menu.style.left = `${left / zoom}px`
  menu.style.top = `${top / zoom}px`
}
