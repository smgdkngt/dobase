// A tool's own page in a frame: beside another tool (side_pane_controller.js) or as a
// tile in the workspace (workspace_controller.js). What both do with such a frame.

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

// The name is how the page in the frame knows where it is (application.js)
export function toolFrame(url, name) {
  const frame = document.createElement("iframe")
  frame.src = url
  frame.name = name
  frame.title = "Tool"
  // A call in a room asks for these itself
  frame.allow = "camera; microphone; display-capture; fullscreen; clipboard-write"
  return frame
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
  const message = "Something there isn't finished: an unsent message, or a call. Close it anyway?"
  return Turbo.config.forms.confirm(message, null, { dataset: { turboConfirmButton: "Close" } })
}
