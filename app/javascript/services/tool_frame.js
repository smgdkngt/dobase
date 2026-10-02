// A tool's own page in a frame: a tile in the workspace (workspace_controller.js).
// What the workspace does with such a frame.

// "/tools/12/board?card=3" from an address on this site; nothing from any other.
// A path can itself start with two slashes ("/.//elsewhere.example"), which a frame
// would read as another site.
export function pathOf(url) {
  if (!url) return null

  try {
    const address = new URL(url, location.origin)
    const path = address.pathname + address.search + address.hash
    return address.origin === location.origin && !path.startsWith("//") ? path : null
  } catch {
    return null
  }
}

export function toolIdOf(path) {
  return path?.match(/^\/tools\/(\d+)/)?.[1] || null
}

// The name is how the page in the frame knows it is a tile (application.js)
export function toolFrame(url) {
  const frame = document.createElement("iframe")
  frame.src = url
  frame.name = "workspace-tile"
  frame.title = "Tool"
  // A call in a room asks for these itself
  frame.allow = "camera; microphone; display-capture; fullscreen; clipboard-write"
  return frame
}

// A link that goes to a page of a tool, rather than into a frame of the page, to a
// download, or off to do something: what can be opened as a tile of its own
export function opensAsTile(link) {
  if (link.origin !== location.origin || !toolIdOf(link.pathname)) return false
  if (link.hasAttribute("download") || link.dataset.turboMethod || link.dataset.turbo === "false") return false
  if (link.target && link.target !== "_self") return false

  const around = link.closest("turbo-frame")
  const frame = link.dataset.turboFrame || around?.getAttribute("target") || (around ? "frame" : "_top")
  return frame === "_top"
}

// Where the page in a frame is: read from the frame itself, so anything it did to
// its address between visits (a card it opened) counts. Nothing while it is still
// loading its first page, or shows a page that isn't the app's.
export function frameAddress(frame) {
  try {
    const { protocol, pathname, search } = frame.contentWindow.location
    return protocol.startsWith("http") ? pathname + search : null
  } catch {
    return null
  }
}

// Sends the page in a frame somewhere else. False when it wouldn't go: it asked its
// person first (an unsent mail does) and they said no. Turbo in the frame gets there
// without a blank moment and without a step for the back button, and says
// "turbo:visit" at once when the visit is on.
export function sendFrameTo(frame, path) {
  const page = frame.contentWindow

  if (!frameAddress(frame) || !page.Turbo) {
    // Nothing there to ask: still loading, or a page that isn't the app's (an error
    // page). Replaced where the frame lets us, so the back button gets no step for it.
    try {
      page.location.replace(path)
    } catch {
      frame.src = path
    }
    return true
  }

  let leaving = false
  const started = () => { leaving = true }
  page.document.addEventListener("turbo:visit", started, { once: true })
  page.Turbo.visit(path, { action: "replace" })
  page.document.removeEventListener("turbo:visit", started)
  return leaving
}

// An unsent mail, a call: the page says so the way it would tell the browser before
// its tab is closed. Taking a frame away takes its page along without the browser
// asking, so whoever does that asks here first. A document being written sends its
// last words on the same occasion.
export function hasUnfinishedWork(frame) {
  try {
    const page = frame.contentWindow
    const leaving = new page.Event("beforeunload", { cancelable: true })
    page.dispatchEvent(leaving)
    return leaving.defaultPrevented
  } catch {
    return false
  }
}

// The app's own confirmation dialog (application.js), with its button saying Close
export function confirmClosing() {
  const message = "This tile has unfinished work, such as an unsent mail or a call. Close it anyway?"
  return Turbo.config.forms.confirm(message, null, { dataset: { turboConfirmButton: "Close" } })
}
