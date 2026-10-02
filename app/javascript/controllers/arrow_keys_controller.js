import { Controller } from "@hotwired/stimulus"
import { typing } from "services/typing"

// The arrow keys move through what a page is made of: the cards of a board, the rows
// of a list, the files in a folder. Whatever a view marks as an item
// (data-arrow-keys-target="item") can be reached; the key goes to the nearest item
// on that side of the one you are on, so the same rule serves a list, a grid and the
// columns of a board. Enter opens an item, as a click would.
//
// With Shift, an item that can be dragged to another place (sortable_controller.js)
// moves there instead.
//
// Home and End go as far as it goes up or down from where you are (the top of this
// column, the end of this list), Page Up and Page Down about a screen.
//
// A page without items scrolls instead, so reading a document or what is in a dialog
// needs no mouse either: its scroller target, or whatever in it scrolls. There the
// space bar turns the page too. Where there is nothing further to the left, the
// left arrow goes back (the back target: the arrow in a tool's top bar), the way the
// right arrow or Enter went in.
//
// Past the last item on a side the controller says "edge": a view may have something
// of its own to do there (the calendar: another week), and in the workspace the tile
// on that side takes over (tile_page_controller.js), so the arrows go from tool to
// tool as well.
//
// Where you were on a page is kept while the tab is open: coming back to a list, the
// first arrow lands on what you left it by. The keys are left alone while you type,
// and to whatever took them first (a tool with arrows of its own prevents the default).
const SIDES = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right" }
// The keys that go far: which way, and whether all the way or about a screen
const FAR = { Home: [ "up", "end" ], End: [ "down", "end" ], PageUp: [ "up", "page" ], PageDown: [ "down", "page" ] }
const SCROLL_STEP = 80
// How much of what is in sight a page is: a little stays, to read on from
const PAGE = 0.85
const KEPT = "dobase:arrow-keys"
// How much a step sideways counts against a step ahead: the item straight ahead wins
// over a nearer one off to the side
const ASIDE_COSTS = 3

export default class extends Controller {
  static targets = ["item", "scroller", "back"]
  // The one for the page itself, which has the keys when nothing else has the keyboard
  static values = { main: Boolean }

  connect() {
    this._onKey = (event) => this.keyed(event)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  keyed(event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (!this.hasTheKeyboard || typing(event) || somethingOverThePage()) return

    const side = SIDES[event.key]
    if (side) return this.arrow(event, side)
    if (FAR[event.key]) return this.far(event, ...FAR[event.key])
    if (event.key === "Enter" && !event.shiftKey) this.open(event)
    if (event.key === " ") this.space(event)
  }

  // What says it is a button is pressed with the space bar too. On a page that is
  // read (nothing to go through) the space bar turns the page, with Shift back,
  // unless it is on something it presses.
  space(event) {
    const on = document.activeElement
    if (on?.matches("[role='button']")) return this.open(event)
    if (on?.matches("a[href], button, input, summary, [tabindex='0']") || this.items.length > 0) return

    this.scrollFar(event, event.shiftKey ? "up" : "down", "page")
  }

  // Home, End, Page Up, Page Down: from the item you are on as far as it goes that
  // way, or about as far as is in sight
  far(event, side, how) {
    const items = this.items
    if (items.length === 0) return this.scrollFar(event, side, how)

    let to = this.itemWithFocus(items) || this.start(items)
    if (!to) return

    const from = middle(to.getBoundingClientRect()).y
    const page = window.innerHeight * PAGE
    for (let next = this.neighbour(to, side, items); next; next = this.neighbour(to, side, items)) {
      if (how === "page" && Math.abs(middle(next.getBoundingClientRect()).y - from) > page) break
      to = next
    }
    event.preventDefault()
    this.goTo(to)
  }

  scrollFar(event, side, how) {
    const scroller = this.scrollerIn(this.reach)
    if (!scroller) return

    event.preventDefault()
    const down = side === "down"
    if (how === "page") scroller.scrollBy({ top: (down ? 1 : -1) * scroller.clientHeight * PAGE })
    else scroller.scrollTo({ top: down ? scroller.scrollHeight : 0 })
  }

  arrow(event, side) {
    const items = this.items
    if (items.length === 0) return this.scroll(event, side)

    const on = this.itemWithFocus(items)
    if (event.shiftKey) return on && this.move(event, on, side)

    // Not on anything yet: left is the way back out, any other arrow lands on the
    // item to start from. The next ones go on from there.
    if (!on && this.goBack(side)) return event.preventDefault()

    const to = on ? this.neighbour(on, side, items) : this.start(items)
    event.preventDefault()
    if (to) {
      this.goTo(to)
    } else if (!this.goBack(side)) {
      this.pastTheEdge(side, event)
    }
  }

  // Nothing further that way: a view may have something of its own to do there (the
  // calendar goes to the next week), and says so by preventing the default. `repeat`
  // says the key is being held down: an edge is where that stops.
  pastTheEdge(side, event) {
    return this.dispatch("edge", { detail: { side, repeat: Boolean(event?.repeat) }, cancelable: true }).defaultPrevented
  }

  goBack(side) {
    const back = side === "left" && this.backTargets.find(visible)
    if (back) back.click()
    return Boolean(back)
  }

  // Enter on an item that isn't a link or a button by itself
  open(event) {
    const on = this.itemWithFocus(this.items)
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

  // Nothing to go through: up and down read on, left goes back, and a view may have
  // its own idea of what lies to the left and right (the calendar: another week)
  scroll(event, side) {
    // With Shift the arrows select what is being read
    if (event.shiftKey) return

    const reach = this.reach
    if (side === "left" || side === "right") {
      // The key stays free for whoever else wants it (mail's own keys) when nothing
      // was done with it here
      if (reach === this.element && (this.goBack(side) || this.pastTheEdge(side, event))) event.preventDefault()
      return
    }

    const scroller = this.scrollerIn(reach)
    if (!scroller) return

    event.preventDefault()
    scroller.scrollBy({ top: side === "down" ? SCROLL_STEP : -SCROLL_STEP })
  }

  // What scrolls there: the view's scroller, or else the first thing in it that does
  // (a dialog, the part of a card's details that is longer than its room)
  scrollerIn(reach) {
    const named = this.scrollerTargets.find((target) => reach.contains(target) && visible(target))
    if (named) return named
    if (reach === this.element && this.mainValue) return null

    return [ reach, ...Array.from(reach.querySelectorAll("*")).slice(0, 600) ].find(scrolls) || null
  }

  goTo(item) {
    // Anything can be an item; what can't take the keyboard by itself is let to
    if (item.tabIndex < 0 && !item.hasAttribute("tabindex")) item.tabIndex = -1
    item.focus({ preventScroll: true })
    item.scrollIntoView({ block: "nearest", inline: "nearest" })
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

  // ── Which one ──

  get items() {
    const reach = this.reach
    return this.itemTargets.filter((item) => reach.contains(item) && visible(item))
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
