import { Controller } from "@hotwired/stimulus"

// A second tool beside the one you have open.
//
// The tool beside is a page of its own in a frame. The server draws it without the
// sidebar (ApplicationController#side_pane?), and because its window is narrow it
// gets the layout of a narrow screen. This element sits next to <body>, not in it
// (application.js puts it there): Turbo swaps the body on every visit, and a frame
// that moves loads its page again. Out here the tool beside stays as it is, a
// half-written message and all, while the main one goes from page to page.
//
// What is beside, and how wide, is kept in this browser, per person.
const MIN_WIDTH = 320
const DEFAULT_WIDTH = 420
// What the main tool keeps, however wide the pane is asked to be: it has the layout
// of a wide screen, which needs about this much
const MAIN_MIN_WIDTH = 640
const KEY_STEP = 24

export default class extends Controller {
  static targets = ["slot", "resizer"]
  static values = { userId: Number }

  connect() {
    this.root = document.documentElement
    // Room for the sidebar, a main tool and a tool beside it; a narrower window shows
    // one tool, and the tool beside comes back when it is wide again
    this.wide = window.matchMedia("(min-width: 1280px)")
    this.state = this.load()
    this.mainToolId = toolIdOf(location.pathname)

    this.listening = new AbortController()
    this.listen(document, "click", (event) => this.clicked(event), true)
    this.listen(document, "keydown", (event) => this.keyed(event))
    this.listen(document, "turbo:visit", (event) => { this.visitAction = event.detail.action })
    this.listen(document, "turbo:load", () => this.pageChanged())
    // The sidebar is drawn again by the server; say once more what is beside
    this.listen(document, "turbo:render", () => this.markSidebar())
    this.listen(document, "turbo:morph", () => this.markSidebar())
    this.listen(window, "message", (event) => this.heard(event))
    this.listen(window, "resize", () => this.applyWidth())
    this.listen(window, "pagehide", () => this.remember())
    this.listen(window, "side-pane:open", (event) => { if (this.open(event.detail.url)) event.preventDefault() })
    this.listen(window, "side-pane:toggle", (event) => this.toggle(event.detail.url))
    this.listen(window, "theme:change", (event) => this.tell("theme", { theme: event.detail }))
    this.listen(this.wide, "change", () => this.show())

    this.show()
  }

  disconnect() {
    this.listening.abort()
    delete this.root.dataset.sidePane
    this.root.style.removeProperty("--side-pane-width")
  }

  listen(target, type, handler, capture = false) {
    target.addEventListener(type, handler, { capture, signal: this.listening.signal })
  }

  // ── Opening and closing ──

  // True when the pane took it: whoever asked (the command palette) otherwise opens
  // the page the usual way
  open(url) {
    const path = pathOf(url)
    if (!path || !this.wide.matches) return false

    if (this.frame) {
      this.goTo(path)
    } else {
      this.state.url = path
      this.save()
    }
    this.show()
    return true
  }

  // The close button, and the sidebar button of the tool that is beside
  async close() {
    if (this.frameHasUnfinishedWork() && !(await this.confirmed())) return

    this.forget()
  }

  // Closes without asking: the page beside is gone already, or there is nothing on it
  forget() {
    // Focus that was in the pane (its close button, the tool itself) goes to the main tool
    const focusWasHere = this.element.contains(document.activeElement)

    this.state.url = null
    this.save()
    this.show()
    if (focusWasHere) document.getElementById("main-content")?.focus()
  }

  // The button on a tool in the sidebar: beside, or not beside any more
  toggle(url) {
    const path = pathOf(url)
    if (!path) return

    this.shown && toolIdOf(path) === toolIdOf(this.state.url) ? this.close() : this.open(path)
  }

  // The tool beside becomes the main one, and the main one goes beside
  swap() {
    const beside = this.frameAddress || this.state.url
    if (!beside) return

    // Either page may not want to leave (an unsent mail asks first). If the one beside
    // stays, nothing moves; if the main one stays, the one beside goes back.
    if (!this.goTo(location.pathname + location.search)) return
    if (!this.visitMain(beside)) this.goTo(beside)
  }

  // False when the main page wouldn't go. Turbo says "turbo:visit" at once when a visit is on.
  visitMain(url) {
    const started = () => { this.swapping = true }
    this.swapping = false
    document.addEventListener("turbo:visit", started, { once: true })
    Turbo.visit(url)
    document.removeEventListener("turbo:visit", started)
    return this.swapping
  }

  // To the tool beside with the keyboard; F6 there comes back
  focus() {
    this.frame?.contentWindow.focus()
  }

  get shown() {
    return !this.element.hidden
  }

  get frame() {
    return this.slotTarget.querySelector("iframe")
  }

  // Draws what the state says: the page at state.url in a frame, or nothing.
  // A window that is only too narrow keeps the page it has, out of sight: taking the
  // frame away would take a half-written message or a call with it.
  show() {
    const open = Boolean(this.state.url) && this.wide.matches

    this.element.hidden = !open
    if (open) {
      this.root.dataset.sidePane = "open"
      this.applyWidth()
      if (!this.frame) this.slotTarget.append(this.frameFor(this.state.url))
    } else {
      delete this.root.dataset.sidePane
      this.root.style.removeProperty("--side-pane-width")
      if (!this.state.url) this.frame?.remove()
    }
    this.markSidebar()
  }

  // Sends the page beside somewhere else. False when it wouldn't go: it asked its
  // person first (an unsent mail does) and they said no. What is beside is only
  // written down once the page agrees to leave.
  goTo(path) {
    const frame = this.frame
    const page = frame.contentWindow
    let leaving = true

    if (this.frameAddress && page.Turbo) {
      // Turbo in the frame gets there without a blank moment, and without a step for
      // the back button. It says "turbo:visit" at once when the visit is on.
      leaving = false
      const started = () => { leaving = true }
      page.document.addEventListener("turbo:visit", started, { once: true })
      page.Turbo.visit(path, { action: "replace" })
      page.document.removeEventListener("turbo:visit", started)
    } else {
      // Nothing there to ask: still loading, or a page that isn't the app's (an error page)
      frame.replaceWith(this.frameFor(path))
    }

    if (leaving) {
      this.state.url = path
      this.save()
      this.markSidebar()
    }
    return leaving
  }

  frameFor(url) {
    const frame = document.createElement("iframe")
    frame.src = url
    // How the page in it knows it is the one beside (application.js)
    frame.name = "side-pane"
    frame.title = "Tool beside"
    // A call in a room beside asks for these itself
    frame.allow = "camera; microphone; display-capture; fullscreen; clipboard-write"
    return frame
  }

  // Where the page beside is: read from the frame itself, so anything it did to its
  // address between visits (a card it opened) counts. Nothing while it is still
  // loading its first page, or shows a page that isn't the app's.
  get frameAddress() {
    try {
      const { protocol, pathname, search } = this.frame.contentWindow.location
      return protocol.startsWith("http") ? pathname + search : null
    } catch {
      return null
    }
  }

  // An unsent mail, a call: the page beside says so the way it would tell the browser
  // before its tab is closed. A document being written sends its last words on the same
  // occasion.
  frameHasUnfinishedWork() {
    try {
      const page = this.frame.contentWindow
      const leaving = new page.Event("beforeunload", { cancelable: true })
      page.dispatchEvent(leaving)
      return leaving.defaultPrevented
    } catch {
      return false
    }
  }

  // The app's own confirmation dialog (application.js), with its button saying Close
  confirmed() {
    const message = "Something beside isn't finished: an unsent message, or a call. Close it anyway?"
    return Turbo.config.forms.confirm(message, null, { dataset: { turboConfirmButton: "Close" } })
  }

  // ── What the page beside says (side_pane_page_controller.js) ──

  heard(event) {
    const frame = this.frame
    if (!frame || event.origin !== location.origin || event.source !== frame.contentWindow) return

    const message = event.data || {}
    switch (message.sidePane) {
      case "location":
        // Sent away from its tool (deleted, or not yours any more): nothing to keep beside
        if (!toolIdOf(pathOf(message.url))) return this.forget()

        this.state.url = pathOf(message.url)
        this.save()
        frame.title = message.title || "Tool beside"
        this.element.setAttribute("aria-label", `Beside: ${frame.title}`)
        this.markSidebar()
        break
      case "notifications":
        // The bell is on this page
        window.focus()
        document.querySelector("[data-notifications-target='trigger'][data-hotkey]")?.click()
        break
      case "leave":
        window.focus()
        document.getElementById("main-content")?.focus()
        break
      case "gone":
        // Signed out, or a page that isn't a tool's: nothing to keep beside
        this.forget()
        break
    }
  }

  tell(what, details = {}) {
    this.frame?.contentWindow.postMessage({ sidePane: what, ...details }, location.origin)
  }

  // ── The page around it ──

  // Alt and a click on a link to a tool opens it beside instead
  clicked(event) {
    if (!event.altKey || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return
    if (!this.wide.matches) return

    const link = event.target.closest?.("a[href]")
    if (!link || !opensBeside(link)) return

    event.preventDefault()
    event.stopPropagation()
    link.closest("dialog")?.close()
    this.open(link.href)
  }

  // F6 goes to the tool beside, and from there back (side_pane_page_controller.js).
  // Not through the shortcut library: that leaves keys typed in a field alone, and
  // a field is where you usually are.
  keyed(event) {
    if (event.key !== "F6" || !this.shown) return

    event.preventDefault()
    this.focus()
  }

  pageChanged() {
    const toolId = toolIdOf(location.pathname)
    const arrived = toolId && toolId !== this.mainToolId
    // Back and forward return to a page as it was, and leave the pane as it is
    const returned = this.visitAction === "restore"
    // The two just traded places, and the page beside may not have said where it is yet
    const swapped = this.swapping
    this.mainToolId = toolId
    this.visitAction = null
    this.swapping = false

    // The tool that was beside is the main one now: it has moved over
    if (arrived && !returned && !swapped && this.shown && toolId === toolIdOf(this.state.url)) this.close()

    this.markSidebar()
  }

  // The button of the tool that is beside stays lit, and what is beside is seen
  markSidebar() {
    const beside = this.shown ? toolIdOf(this.state.url) : null

    document.querySelectorAll("[data-side-pane-toggle]").forEach((button) => {
      const on = Boolean(beside) && button.dataset.toolId === beside
      button.setAttribute("aria-pressed", on)
      if (on) button.parentElement.querySelector("[data-sidebar-tool-link]")?.removeAttribute("data-unread")
    })
  }

  // ── Width ──

  startResize(event) {
    if (event.button !== 0) return
    event.preventDefault()

    const handle = event.currentTarget
    const dragging = new AbortController()
    const stop = () => {
      dragging.abort()
      delete this.element.dataset.resizing
      this.save()
    }

    // The frame would take the pointer as soon as it is over it
    this.element.dataset.resizing = ""
    handle.setPointerCapture(event.pointerId)
    handle.addEventListener("pointermove", (move) => this.setWidth(window.innerWidth - move.clientX), { signal: dragging.signal })
    handle.addEventListener("pointerup", stop, { signal: dragging.signal })
    handle.addEventListener("pointercancel", stop, { signal: dragging.signal })
  }

  resizeWithKeys(event) {
    const step = { ArrowLeft: KEY_STEP, ArrowRight: -KEY_STEP }[event.key]
    if (!step) return

    event.preventDefault()
    this.setWidth(this.width + step)
    this.save()
  }

  resetWidth() {
    this.setWidth(DEFAULT_WIDTH)
    this.save()
  }

  setWidth(width) {
    this.state.width = this.fitting(width)
    this.applyWidth()
  }

  get width() {
    return this.fitting(this.state.width || DEFAULT_WIDTH)
  }

  // As wide as asked, as long as the main tool keeps room; never too narrow to use
  fitting(width) {
    const sidebar = parseFloat(getComputedStyle(this.root).getPropertyValue("--sidebar-width")) || 0
    const room = window.innerWidth - sidebar - MAIN_MIN_WIDTH
    return Math.round(Math.max(MIN_WIDTH, Math.min(width, room)))
  }

  applyWidth() {
    if (!this.shown) return

    this.root.style.setProperty("--side-pane-width", `${this.width}px`)
    this.resizerTarget.setAttribute("aria-valuemin", MIN_WIDTH)
    this.resizerTarget.setAttribute("aria-valuemax", this.fitting(Infinity))
    this.resizerTarget.setAttribute("aria-valuenow", this.width)
  }

  // ── Remembering ──

  get storageKey() {
    return `dobase:side-pane:${this.userIdValue}`
  }

  load() {
    try {
      const kept = JSON.parse(localStorage.getItem(this.storageKey)) || {}
      const url = pathOf(kept.url)
      // Only ever a tool's page: that is all the pane writes here
      return { url: toolIdOf(url) ? url : null, width: Number(kept.width) || DEFAULT_WIDTH }
    } catch {
      return { url: null, width: DEFAULT_WIDTH }
    }
  }

  save() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(this.state))
    } catch {
      // No storage (private browsing, a full disk): the pane works, and is gone after a reload
    }
  }

  remember() {
    if (!this.frameAddress) return

    this.state.url = this.frameAddress
    this.save()
  }
}

// "/tools/12/board?card=3" from an address on this site; nothing from any other.
// A path can itself start with two slashes ("/.//elsewhere.example"), which a frame
// would read as another site.
function pathOf(url) {
  if (!url) return null

  try {
    const address = new URL(url, location.origin)
    const path = address.pathname + address.search + address.hash
    return address.origin === location.origin && !path.startsWith("//") ? path : null
  } catch {
    return null
  }
}

function toolIdOf(path) {
  return path?.match(/^\/tools\/(\d+)/)?.[1] || null
}

// A link that goes to a page of a tool, rather than into a frame, to a download
// or off to do something
function opensBeside(link) {
  if (link.origin !== location.origin || !toolIdOf(link.pathname)) return false
  if (link.hasAttribute("download") || link.dataset.turboMethod || link.dataset.turbo === "false") return false
  if (link.target && link.target !== "_self") return false

  const frame = link.dataset.turboFrame || link.closest("turbo-frame")?.getAttribute("target") || (link.closest("turbo-frame") ? "frame" : "_top")
  return frame === "_top"
}
