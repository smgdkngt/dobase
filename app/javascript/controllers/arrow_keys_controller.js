import { Controller } from "@hotwired/stimulus"
import { typing } from "services/typing"

// The arrow keys go through everything on a page that takes the keyboard. First what
// the page is made of, which a view marks as items (data-arrow-keys-target="item"):
// the cards of a board, the rows of a list, the files in a folder. Where those run
// out on a side, whatever else can be pressed there: a filter, the buttons of a top
// bar, what a detail view has. The key goes to the nearest one on that side of where
// you are, so one rule serves a list, a grid, the columns of a board and a toolbar
// above them. Enter opens an item, as a click would.
//
// With Shift, an item that can be dragged to another place (sortable_controller.js)
// moves there instead. Home and End go as far as it goes up or down among the items
// (the top of this column, the end of this list), Page Up and Page Down about a screen.
//
// A page that is read (a document, a mail: nothing marked) scrolls with up and down
// and turns with the space bar; the right arrow goes to what can be pressed on it,
// and from there the arrows go on through that. What lies further off than is in
// sight is come nearer to first, so a long text is read on the way to what is under
// it. In a dialog or a menu it is the same, within that dialog or menu.
//
// In a field the arrows move the caret. Where the caret can go no further that way
// (the start or the end of the text, up or down in a field of one line, anywhere in
// an empty one) they go on to what lies beyond, so a form is gone through without
// the Tab key. Escape lets go of a field on the page (keyboard_shortcuts_controller.js).
//
// Where there is nothing further to the left, the left arrow goes back (the back
// target: the arrow in a tool's top bar), the way the right arrow or Enter went in.
// Past the last thing on a side the controller says "edge": a view may have something
// of its own to do there (the calendar: another week), and in the workspace the tile
// on that side takes over (tile_page_controller.js), so the arrows go from tool to
// tool as well.
//
// Where you were on a page is kept while the tab is open: coming back to a list, the
// first arrow lands on what you left it by. The keys are left alone while you type,
// and to whatever took them first (a tool with arrows of its own prevents the
// default). The controller on <body> (over: true) is there for the dialogs and menus
// that lie outside any page's own controller.

const SIDES = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right" }
// The keys that go far: which way, and whether all the way or about a screen
const FAR = { Home: [ "up", "end" ], End: [ "down", "end" ], PageUp: [ "up", "page" ], PageDown: [ "down", "page" ] }
const SCROLL_STEP = 80
// How much of what is in sight a page is: a little stays, to read on from
const PAGE = 0.85
const KEPT = "dobase:arrow-keys"
// What takes the keyboard by itself
const TAKES_KEYS = "a[href], button, input:not([type='hidden']), select, textarea, summary, [role='button'], [tabindex]:not([tabindex='-1']), [contenteditable='true']"
// A field with one line: up and down have nothing to do in it
const ONE_LINE = "input:not([type]), input[type='text'], input[type='email'], input[type='password'], input[type='search'], input[type='url'], input[type='tel']"
// Fields whose value isn't moved through with a caret: the arrows go on from them
// (the space bar opens a list to choose from; a date is typed)
const NO_CARET = "select, input[type='date'], input[type='time'], input[type='datetime-local'], input[type='month'], input[type='week'], input[type='color'], input[type='file']"
// How much a step sideways counts against a step ahead: the item straight ahead wins
// over a nearer one off to the side
const ASIDE_COSTS = 3

export default class extends Controller {
  static targets = ["item", "scroller", "back"]
  // main: the one for the page itself, which has the keys when nothing else has the
  // keyboard. over: the one on <body>, only for what lies over a page (a dialog, a menu).
  static values = { main: Boolean, over: Boolean }

  connect() {
    this._onKey = (event) => this.keyed(event)
    document.addEventListener("keydown", this._onKey)
    if (!this.overValue) return

    // A menu that opens takes the keyboard to its first entry, so the arrows go
    // through it from there (the browser leaves the keyboard on what opened it)
    this._onMenu = (event) => {
      const menu = event.target
      if (event.newState !== "open" || !menu.matches?.("[popover='auto']") || menu.contains(document.activeElement)) return

      Array.from(menu.querySelectorAll(TAKES_KEYS)).find(pressable)?.focus()
    }
    document.addEventListener("toggle", this._onMenu, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    if (this._onMenu) document.removeEventListener("toggle", this._onMenu, true)
  }

  keyed(event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (!this.hasTheKeyboard || somethingOverThePage()) return
    if (this.overValue && !this.overThePage) return

    const side = SIDES[event.key]
    // In a field the arrows are the caret's, until it is at the end of what there is
    // to move through that way: then they go on, so no field on the way holds the
    // keyboard (leavesField, below)
    if (typing(event) && !(side && leavesField(event.composedPath()[0] || event.target, side))) return

    if (side) return this.arrow(event, side)
    if (FAR[event.key]) return this.far(event, ...FAR[event.key])
    if (event.key === "Enter" && !event.shiftKey) this.open(event)
    if (event.key === " ") this.space(event)
  }

  arrow(event, side) {
    const marked = this.marked
    const others = this.others
    if (marked.length === 0 && others.length === 0) return this.scroll(event, side)

    const active = document.activeElement
    const item = marked.find((one) => one === active)
    // Something of an item's own that has the keyboard: a file's menu, a message's reply
    const owner = item ? null : marked.find((one) => one.contains(active))
    const on = item || (owner ? active : others.find((other) => other === active)) || null
    if (event.shiftKey) return item && this.move(event, item, side)
    if (!on) return this.first(event, side, marked, others)

    const to = this.next(on, side, { item, owner, marked, others })
    if (!to) return this.nothingFurther(event, side, marked)

    event.preventDefault()
    // Further off than is in sight, and not one of the view's own rows: nearer first
    const upOrDown = side === "up" || side === "down"
    if (upOrDown && !marked.includes(to) && !showing(to) && this.comeNearer(to, side)) return

    this.goTo(to)
  }

  // Where an arrow goes from what has the keyboard:
  //
  // - from one of the view's items to the next item on that side; where the items run
  //   out, into what the item has of its own on that side (the buttons at the end of
  //   a row), and then to whatever else is there (a filter, the top bar);
  // - from something of an item's own to the next of those, and past them back to
  //   the item or on to the rest;
  // - from anything else to whatever is nearest, an item or not. Back among the items
  //   that is the one you left them by when it lies that way, not the one that
  //   happens to be level.
  next(on, side, { item, owner, marked, others }) {
    if (item) return this.neighbour(item, side, marked) || this.within(item, side) || this.neighbour(item, side, others)

    if (owner) {
      const beside = this.neighbour(on, side, this.ownOf(owner))
      if (beside) return beside
      if (lies(owner, side, on)) return owner

      return this.neighbour(owner, side, marked) || this.neighbour(on, side, others)
    }

    const to = this.neighbour(on, side, [ ...marked, ...others ])
    const left = this.last
    return to && marked.includes(to) && marked.includes(left) && this.neighbour(on, side, [ left ]) ? left : to
  }

  // What an item has of its own that takes the keyboard
  ownOf(item) {
    return Array.from(item.querySelectorAll(TAKES_KEYS)).filter((element) => pressable(element) && !this.itemTargets.includes(element))
  }

  // The first of an item's own things on that side of its middle
  within(item, side) {
    const own = this.ownOf(item).filter((element) => lies(element, side, item))
    if (own.length === 0) return null

    const from = middle(item.getBoundingClientRect())
    const far = (element) => Math.hypot(middle(element.getBoundingClientRect()).x - from.x, middle(element.getBoundingClientRect()).y - from.y)
    return own.reduce((nearest, element) => (far(element) < far(nearest) ? element : nearest))
  }

  // Not on anything yet. Left is the way back out. On a page that is read, up and
  // down read on. Any other arrow lands on what there is to start from: the item you
  // were on before, or the first in sight.
  first(event, side, marked, others) {
    if (side === "left") {
      if (this.goBack(side) || (!this.overThePage && this.pastTheEdge(side, event))) event.preventDefault()
      return
    }
    // A page that is read: up and down read on. One with nothing to read on (it all
    // fits) starts on what there is, like any other.
    if (marked.length === 0 && !this.inDialog && side !== "right" && this.scrollerIn(this.reach, { any: true })) return this.scroll(event, side)

    const to = this.start(marked.length > 0 ? marked : others)
    if (!to) return

    event.preventDefault()
    this.goTo(to)
  }

  // Nothing further that way. What is longer than its room scrolls (a dialog, a page
  // that is read); then the left arrow goes back, and the edge is said.
  nothingFurther(event, side, marked) {
    const upOrDown = side === "up" || side === "down"
    if (upOrDown && (this.overThePage || marked.length === 0)) {
      const scroller = this.scrollerIn(this.reach, { any: true })
      if (scroller && !atTheEnd(scroller, side)) {
        event.preventDefault()
        return scroller.scrollBy({ top: side === "down" ? SCROLL_STEP : -SCROLL_STEP })
      }
    }
    // Nothing behind a dialog or a menu is reached from it
    if (this.inDialog) return

    if (this.goBack(side) || (!this.overThePage && this.pastTheEdge(side, event)) || !this.overThePage) event.preventDefault()
  }

  // Something further off than is in sight: what it lies in scrolls a step that way.
  // False when it can't (then the keyboard just goes there).
  comeNearer(to, side) {
    const scroller = scrollerAround(to)
    if (!scroller || atTheEnd(scroller, side)) return false

    scroller.scrollBy({ top: side === "down" ? SCROLL_STEP : -SCROLL_STEP })
    return true
  }

  // What says it is a button is pressed with the space bar too. On a page that is
  // read the space bar turns the page, with Shift back, unless it is on something
  // it presses.
  space(event) {
    const on = document.activeElement
    if (on?.matches("[role='button']")) return this.open(event)
    if (on?.matches("a[href], button, input, summary, [tabindex='0']") || this.marked.length > 0) return

    this.scrollFar(event, event.shiftKey ? "up" : "down", "page")
  }

  // Home, End, Page Up, Page Down: among the view's items, from the one you are on as
  // far as it goes that way, or about as far as is in sight. Where there are none,
  // what is read scrolls that far.
  far(event, side, how) {
    const marked = this.marked
    if (marked.length === 0) return this.scrollFar(event, side, how)

    let to = this.itemWithFocus(marked) || this.start(marked)
    if (!to) return

    const from = middle(to.getBoundingClientRect()).y
    const page = window.innerHeight * PAGE
    for (let next = this.neighbour(to, side, marked); next; next = this.neighbour(to, side, marked)) {
      if (how === "page" && Math.abs(middle(next.getBoundingClientRect()).y - from) > page) break
      to = next
    }
    event.preventDefault()
    this.goTo(to)
  }

  scrollFar(event, side, how) {
    const scroller = this.scrollerIn(this.reach, { any: true })
    if (!scroller) return

    event.preventDefault()
    const down = side === "down"
    if (how === "page") scroller.scrollBy({ top: (down ? 1 : -1) * scroller.clientHeight * PAGE })
    else scroller.scrollTo({ top: down ? scroller.scrollHeight : 0 })
  }

  // Nothing further that way: a view may have something of its own to do there (the
  // calendar goes to the next week), and says so by preventing the default. `repeat`
  // says the key is being held down: an edge is where that stops.
  pastTheEdge(side, event) {
    return this.dispatch("edge", { detail: { side, repeat: Boolean(event?.repeat) }, cancelable: true }).defaultPrevented
  }

  goBack(side) {
    const reach = this.reach
    const back = side === "left" && this.backTargets.find((target) => visible(target) && reach.contains(target))
    if (back) back.click()
    return Boolean(back)
  }

  // Enter on an item that isn't a link or a button by itself
  open(event) {
    const on = this.itemWithFocus(this.marked)
    if (!on || on !== document.activeElement) return
    if (on.matches("a[href], button, input, summary, [data-action*='keydown']")) return

    event.preventDefault()
    on.click()
  }

  // An item that can be dragged goes one place that way: up or down among its
  // siblings, or across to the list beside it
  move(event, item, side) {
    const piece = item.closest("[data-sort-id]")
    const list = piece?.parentElement.closest("[data-controller~='sortable']")
    const sortable = list && this.application.getControllerForElementAndIdentifier(list, "sortable")
    if (!sortable?.moveWithKeys) return

    event.preventDefault()
    if (sortable.moveWithKeys(piece, side)) this.goTo(item)
  }

  // Nothing to land on: up and down read on, left goes back, and at the end of what
  // there is to read, as to the left and right, the edge is said
  scroll(event, side) {
    // With Shift the arrows select what is being read
    if (event.shiftKey) return

    const reach = this.reach
    if (side === "up" || side === "down") {
      const scroller = this.scrollerIn(reach, { any: this.marked.length === 0 })
      if (scroller && !atTheEnd(scroller, side)) {
        event.preventDefault()
        return scroller.scrollBy({ top: side === "down" ? SCROLL_STEP : -SCROLL_STEP })
      }
    }
    // The key stays free for whoever else wants it when nothing was done with it here
    if (reach === this.element && (this.goBack(side) || this.pastTheEdge(side, event))) event.preventDefault()
  }

  // What scrolls there: the view's scroller, or else (in a dialog, on a page that is
  // read) the first thing in it that does
  scrollerIn(reach, { any = false } = {}) {
    const named = this.scrollerTargets.find((target) => reach.contains(target) && visible(target))
    if (named) return named
    if (!any && !this.overThePage) return null

    return [ reach, ...Array.from(reach.querySelectorAll("*")).slice(0, 800) ].find(scrolls) || null
  }

  goTo(item) {
    // Anything can be an item; what can't take the keyboard by itself is let to
    if (item.tabIndex < 0 && !item.hasAttribute("tabindex")) item.tabIndex = -1
    item.focus({ preventScroll: true })
    item.scrollIntoView({ block: "nearest", inline: "nearest" })
    // For a view that has more to do when the keyboard gets somewhere (mail opens the
    // conversation beside the list)
    item.dispatchEvent(new CustomEvent("arrow-keys:went", { bubbles: true }))
    if (!this.itemTargets.includes(item)) return

    this.last = item
    this.keep(item)
  }

  // Where you were on this page, for when you come back to it (a list you opened
  // something from): by what the item is, not where it stood
  keep(item) {
    if (!this.mainValue) return

    try {
      sessionStorage.setItem(`${KEPT}:${location.pathname}${location.search}`, this.nameOf(item))
    } catch {
      // No storage: the first arrow starts at the top again
    }
  }

  kept(items) {
    if (!this.mainValue) return null

    try {
      const name = sessionStorage.getItem(`${KEPT}:${location.pathname}${location.search}`)
      return (name && items.find((item) => this.nameOf(item) === name)) || null
    } catch {
      return null
    }
  }

  nameOf(item) {
    return item.id ? `#${item.id}` : item.getAttribute("href") || `at ${this.itemTargets.indexOf(item)}`
  }

  // ── What there is ──

  // What the view says the arrows go through
  get marked() {
    const reach = this.reach
    return this.itemTargets.filter((item) => reach.contains(item) && visible(item))
  }

  // Whatever else takes the keyboard there: not one of the items or something in one
  // (a file's own buttons belong to the file), and not what a view keeps out
  // (data-arrow-keys-skip: a list that has keys of its own)
  get others() {
    const items = this.itemTargets
    return Array.from(this.reach.querySelectorAll(TAKES_KEYS)).filter((element) => {
      return pressable(element) && !element.closest("[data-arrow-keys-skip]") && !items.some((item) => item.contains(element))
    })
  }

  // Whether the keyboard is in a dialog or a menu that is open over the page
  get overThePage() {
    return this.reach !== this.element
  }

  get inDialog() {
    return this.reach.matches("dialog, [popover]")
  }

  itemWithFocus(items) {
    const active = document.activeElement
    return items.find((item) => item === active) || items.find((item) => item.contains(active)) || null
  }

  // Where the first press lands: the item a view says is the current one, the one you
  // were on before, or the first that is in sight. A list that grows at its end (a
  // chat) says data-arrow-keys-from="end", and starts from its last item.
  start(items) {
    const current = items.find((item) => item.matches("[aria-current], [aria-selected='true']"))
    if (current) return current
    if (this.last && items.includes(this.last)) return this.last

    const fromEnd = items.filter((item) => item.closest("[data-arrow-keys-from='end']"))
    // A row's name rather than the checkbox in front of it
    return fromEnd.at(-1) || this.kept(items) || items.find((item) => inSight(item) && !item.matches("input")) || items.find(inSight) || items[0]
  }

  // The nearest item on that side. Distance is what lies between the two ahead, plus
  // what they are apart sideways, which counts for more.
  neighbour(from, side, items) {
    const here = from.getBoundingClientRect()
    const sideways = side === "left" || side === "right"
    let best = null
    let bestCost = Infinity

    for (const item of items) {
      if (item === from) continue

      const there = item.getBoundingClientRect()
      const ahead = {
        up: here.top - there.bottom, down: there.top - here.bottom,
        left: here.left - there.right, right: there.left - here.right
      }[side]
      // On that side at all: its middle lies beyond ours
      const beyond = {
        up: middle(there).y < middle(here).y, down: middle(there).y > middle(here).y,
        left: middle(there).x < middle(here).x, right: middle(there).x > middle(here).x
      }[side]
      if (!beyond || ahead < -Math.min(sideways ? here.width : here.height, sideways ? there.width : there.height) / 2) continue

      const aside = sideways ? apart(here.top, here.bottom, there.top, there.bottom) : apart(here.left, here.right, there.left, there.right)
      const cost = Math.max(0, ahead) + aside * ASIDE_COSTS
      if (cost < bestCost) {
        best = item
        bestCost = cost
      }
    }
    return best
  }

  // The keys are this controller's when the keyboard is somewhere in its element, and
  // not in one of these nested deeper. The one for the page also has them when the
  // keyboard is nowhere in particular, unless a dialog is open over the page.
  get hasTheKeyboard() {
    const active = document.activeElement
    const nowhere = !active || active === document.body || active === document.documentElement

    if (nowhere) return this.mainValue && !document.querySelector("dialog[open]")
    return this.element.contains(active) && active.closest("[data-controller~='arrow-keys']") === this.element
  }

  // With the keyboard in a dialog or a menu that is open, only what is in there counts
  get reach() {
    const over = document.activeElement?.closest?.("dialog[open], [popover]:popover-open")
    return over && this.element.contains(over) ? over : this.element
  }
}

// A viewer that lies over the page without being a <dialog> (the picture gallery) has
// the arrow keys to itself
function somethingOverThePage() {
  return Array.from(document.querySelectorAll("[aria-modal='true']:not(dialog)")).some(visible)
}

function visible(element) {
  return element.getClientRects().length > 0 && !element.closest("[inert]")
}

// Takes the keyboard right now
// (not something that is there for a screen reader or behind a button: those are a
// dot of a pixel)
function pressable(element) {
  if (element.disabled || !(element.tabIndex >= 0 || element.isContentEditable) || !visible(element)) return false

  const { width, height } = element.getBoundingClientRect()
  // (or something no pointer can press either: what lies under a button to do its work)
  return width > 4 && height > 4 && getComputedStyle(element).pointerEvents !== "none"
}

// Whether an arrow that way has nothing left to do in the field it is typed in: the
// caret is at that end of the text (or the field has none to move through)
function leavesField(field, side) {
  if (!(field instanceof HTMLElement)) return false
  if (field.matches(NO_CARET)) return true
  // A group of radio buttons, a slider: the arrows are the choice
  if (field.matches("input[type='radio'], input[type='range'], input[type='number'], [role='slider'], [role='tab'], [role='menuitem'], [role='option']")) return false

  const back = side === "up" || side === "left"
  if (field.matches("input, textarea")) {
    if (field.list) return false
    if (field.matches(ONE_LINE) && (side === "up" || side === "down")) return true

    let at, end
    try {
      at = back ? field.selectionStart : field.selectionEnd
      end = field.selectionStart !== field.selectionEnd
    } catch {
      return false
    }
    // (some kinds of field don't say where the caret is: then only when empty)
    if (at === null || at === undefined) return field.value === ""
    return !end && (back ? at === 0 : at === field.value.length)
  }

  // Something edited in place: the text before the caret, or after it, within it
  const host = field.closest("[contenteditable='true']") || field
  const selection = (host.getRootNode().getSelection?.() || window.getSelection())
  if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) return false

  try {
    const rest = document.createRange()
    rest.selectNodeContents(host)
    back ? rest.setEnd(selection.anchorNode, selection.anchorOffset) : rest.setStart(selection.anchorNode, selection.anchorOffset)
    return rest.toString().trim() === ""
  } catch {
    // The caret is somewhere else than in this field
    return false
  }
}

// Whether something lies on that side of the middle of something else
function lies(element, side, of) {
  const there = middle(element.getBoundingClientRect())
  const here = middle(of.getBoundingClientRect())
  return { up: there.y < here.y, down: there.y > here.y, left: there.x < here.x, right: there.x > here.x }[side]
}

// In sight within everything it lies in that scrolls, not only within the window
function showing(element) {
  const box = element.getBoundingClientRect()
  let top = 0
  let bottom = window.innerHeight
  for (let around = element.parentElement; around; around = around.parentElement) {
    if (!scrolls(around)) continue

    const room = around.getBoundingClientRect()
    top = Math.max(top, room.top)
    bottom = Math.min(bottom, room.bottom)
  }
  return box.bottom > top && box.top < bottom
}

function scrollerAround(element) {
  for (let around = element.parentElement; around; around = around.parentElement) {
    if (scrolls(around)) return around
  }
  return null
}

// As far as it scrolls that way
function atTheEnd(scroller, side) {
  return side === "down" ? scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 1 : scroller.scrollTop <= 0
}

// Longer than its room, and made to scroll
function scrolls(element) {
  return element.scrollHeight > element.clientHeight + 1 && /auto|scroll/.test(getComputedStyle(element).overflowY)
}

function inSight(element) {
  const { top, bottom, left, right } = element.getBoundingClientRect()
  return bottom > 0 && right > 0 && top < window.innerHeight && left < window.innerWidth
}

function middle(rect) {
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }
}

// How far two stretches are apart: nothing when they overlap
function apart(start, end, otherStart, otherEnd) {
  return Math.max(0, Math.max(start, otherStart) - Math.min(end, otherEnd))
}
