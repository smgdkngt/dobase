// On a phone a dialog is a sheet from the bottom edge (layout.css), and like a phone's
// own sheets it is pulled down to close it: by its top, where the grabber is, or
// anywhere on it while what it holds is scrolled to its top.

/** How far a sheet is pulled, in pixels, before letting go of it closes it */
export const CLOSING_DISTANCE = 96

/** How fast a short pull has to be, in pixels a millisecond, to close it as well */
export const CLOSING_SPEED = 0.5

/**
 * Whether a pull that ends here closes the sheet
 * @param {number} distance how far down it was pulled (negative: up)
 * @param {number} milliseconds how long the pull took
 * @returns {boolean}
 */
export function closes(distance, milliseconds) {
  if (distance <= 0) return false
  if (distance >= CLOSING_DISTANCE) return true
  return milliseconds > 0 && distance / milliseconds >= CLOSING_SPEED && distance >= 24
}

/**
 * Whether a finger's first move is a pull down, not a scroll up or sideways
 * @param {number} down
 * @param {number} sideways
 * @returns {boolean}
 */
export function pullsDown(down, sideways) {
  return down > 0 && down >= Math.abs(sideways)
}

const PHONE = "(max-width: 639px)"
const GRAB_HEIGHT = 56

/**
 * Lets the open sheets of this document be pulled down to close
 * @param {Document} document
 */
export function listen(document) {
  /** @type {{ sheet: HTMLDialogElement, startX: number, startY: number, startTime: number, distance: number, pulling: boolean } | null} */
  let pull = null

  document.addEventListener("touchstart", (event) => {
    const target = /** @type {Element} */ (event.target)
    const sheet = /** @type {HTMLDialogElement | null} */ (target.closest?.("dialog.modal-dialog[open]"))
    if (!sheet || event.touches.length !== 1 || !matchMedia(PHONE).matches) return
    // A field or an editor keeps its own gestures (selecting text)
    if (target.closest("input, textarea, select, [contenteditable=true], rhino-editor")) return

    const touch = event.touches[0]
    const top = sheet.getBoundingClientRect().top
    if (touch.clientY - top > GRAB_HEIGHT && scrolledDown(target, sheet)) return

    pull = { sheet, startX: touch.clientX, startY: touch.clientY, startTime: event.timeStamp, distance: 0, pulling: false }
  }, { passive: true })

  document.addEventListener("touchmove", (event) => {
    if (!pull) return
    const touch = event.touches[0]
    const down = touch.clientY - pull.startY
    if (!pull.pulling) {
      if (Math.abs(down) < 4 && Math.abs(touch.clientX - pull.startX) < 4) return
      // Scrolling what the sheet holds, or sideways: not a pull
      if (!pullsDown(down, touch.clientX - pull.startX)) {
        pull = null
        return
      }
      pull.pulling = true
    }
    pull.distance = Math.max(0, down)
    pull.sheet.style.transition = "none"
    pull.sheet.style.transform = `translateY(${pull.distance}px)`
  }, { passive: true })

  const letGo = (/** @type {TouchEvent} */ event) => {
    if (!pull) return
    const { sheet, distance, startTime, pulling } = pull
    pull = null
    if (!pulling) return
    sheet.style.transition = ""
    sheet.style.transform = ""
    if (event.type === "touchend" && closes(distance, event.timeStamp - startTime)) {
      // As Escape would: whoever has unsent work in it can still say no
      if (typeof sheet.requestClose === "function") sheet.requestClose()
      else sheet.close()
    }
  }
  document.addEventListener("touchend", letGo)
  document.addEventListener("touchcancel", letGo)
}

/**
 * Whether anything between the touch and the sheet is scrolled away from its top,
 * so a pull down scrolls it instead
 * @param {Element} target
 * @param {Element} sheet
 * @returns {boolean}
 */
function scrolledDown(target, sheet) {
  for (let element = /** @type {Element | null} */ (target); element && element !== sheet.parentElement; element = element.parentElement) {
    if (element.scrollTop > 0) return true
  }
  return false
}
