// Client-side toast, for messages triggered by a JS fetch rather than a full
// page load (where the server-rendered shared/_flash partial handles it).
// Mirrors that partial's markup/classes so it looks and behaves the same —
// including being picked up by the existing "flash" Stimulus controller
// already connected to #flash (dismiss button, click-outside-free auto-remove).
/** @type {Record<string, string>} */
const ICONS = {
  alert: '<circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/>',
  notice: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'
}

const CLOSE_ICON = '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'

/**
 * @param {string} paths
 * @param {number} size
 */
function svg(paths, size) {
  const xmlns = "http://www.w3.org/2000/svg"
  const icon = document.createElementNS(xmlns, "svg")
  icon.setAttribute("width", String(size))
  icon.setAttribute("height", String(size))
  icon.setAttribute("viewBox", "0 0 24 24")
  icon.setAttribute("fill", "none")
  icon.setAttribute("stroke", "currentColor")
  icon.setAttribute("stroke-width", "2")
  icon.setAttribute("stroke-linecap", "round")
  icon.setAttribute("stroke-linejoin", "round")
  icon.setAttribute("class", "shrink-0")
  icon.setAttribute("aria-hidden", "true")
  icon.innerHTML = paths
  return icon
}

// How long a message stays, a little longer with an Undo button to get to
export const SHOWN_FOR = 5000
export const SHOWN_FOR_WITH_UNDO = 8000

// Takes the message away after `ms`, but not while the pointer or the keyboard is on
// it: then it waits that long again once they have left
/**
 * @param {HTMLElement} element
 * @param {number} ms
 * @param {(element: HTMLElement) => void} dismiss
 */
export function dismissLater(element, ms, dismiss) {
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timer
  const start = () => { clearTimeout(timer); timer = setTimeout(() => dismiss(element), ms) }
  const stop = () => clearTimeout(timer)
  element.addEventListener("mouseenter", stop)
  element.addEventListener("mouseleave", start)
  element.addEventListener("focusin", stop)
  element.addEventListener("focusout", (event) => { if (!element.contains(/** @type {Node | null} */ (event.relatedTarget))) start() })
  start()
}

// type: "alert" (default) or "notice". undo: the form of an Undo button (shared/flash_undo)
/**
 * @param {string} message
 * @param {string} [type]
 * @param {{ undo?: Element | null }} [options]
 */
export function showFlash(message, type = "alert", { undo } = {}) {
  const container = document.getElementById("flash")
  if (!container) return

  const el = document.createElement("div")
  el.className = `flash flash-${type}`
  el.setAttribute("role", "alert")
  el.dataset.flashTarget = "message"
  el.dataset.flashKind = type
  el.dataset.turboTemporary = ""
  el.dataset.action = "click->flash#dismiss"

  const text = document.createElement("span")
  text.className = "flex-1"
  text.dataset.flashText = ""
  text.textContent = message

  const dismiss = document.createElement("button")
  dismiss.type = "button"
  dismiss.className = "ms-2 opacity-70 hover:opacity-100"
  dismiss.dataset.action = "click->flash#dismiss"
  dismiss.appendChild(svg(CLOSE_ICON, 16))

  el.append(svg(ICONS[type] || ICONS.alert, 18), text)
  if (undo) el.append(undo)
  el.append(dismiss)
  container.appendChild(el)
  dismissLater(el, undo ? SHOWN_FOR_WITH_UNDO : SHOWN_FOR, () => el.remove())
}

// The messages of a page that was fetched but isn't drawn as it came (a tile's form that
// Turbo made of a link: the workspace takes the tile to that page itself, which says
// nothing a second time). An Undo button among them undoes in `frame`, the tile.
/**
 * @param {string} html
 * @param {{ frame?: string }} [options]
 */
export function showFlashesOf(html, { frame } = {}) {
  const page = new DOMParser().parseFromString(html, "text/html")
  for (const message of page.querySelectorAll("[data-flash-target='message']")) {
    const undo = message.querySelector("[data-flash-undo]")
    if (undo instanceof HTMLFormElement) {
      undo.remove()
      if (frame) undo.dataset.turboFrame = frame
    }
    const text = message.querySelector("[data-flash-text]")?.textContent?.trim() || ""
    if (text) showFlash(text, message.getAttribute("data-flash-kind") === "notice" ? "notice" : "alert", { undo: undo ? document.importNode(undo, true) : null })
  }
}
