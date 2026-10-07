// When a page that heard "something in this tool changed" draws itself again
// (live_controller.js; the word is Tool#announce_change's).
//
// Not the moment it hears it:
// - Changes come in rows (twenty cards made from a terminal), and one drawing shows
//   them all: a page waits a moment for what follows, and rests between drawings.
// - A page someone is busy in (a dialog open, a field being typed in, something being
//   dragged) or nobody is looking at stays as it is. It knows it is behind, and looks
//   again a little later until it is free.

/** How long a page waits for more to come before it draws */
export const SETTLE_MS = 300
/** The least time between two drawings */
export const REST_MS = 1500
/** How often a page that is behind and busy looks whether it is free */
export const RETRY_MS = 1000

/**
 * @param {object} page
 * @param {() => void} page.draw draws the page again
 * @param {() => boolean} page.busy whether drawing now would take something away
 * @param {number} [page.settle]
 * @param {number} [page.rest]
 * @param {number} [page.retry]
 */
export function refresher({ draw, busy, settle = SETTLE_MS, rest = REST_MS, retry = RETRY_MS }) {
  let behind = false
  let drawnAt = -Infinity
  /** @type {ReturnType<typeof setTimeout> | null} */
  let timer = null

  /** @param {number} wait */
  const plan = (wait) => {
    timer ??= setTimeout(attempt, Math.max(wait, drawnAt + rest - Date.now()))
  }

  const attempt = () => {
    timer = null
    if (!behind) return
    if (busy()) return plan(retry)

    behind = false
    drawnAt = Date.now()
    draw()
  }

  const forget = () => {
    if (timer) clearTimeout(timer)
    timer = null
  }

  return {
    /** Something changed: draw soon, once for everything that comes with it */
    changed() {
      behind = true
      plan(settle)
    },

    /** The page may be free now (it is looked at again): no need to wait for the next look */
    look() {
      if (!behind) return

      forget()
      plan(0)
    },

    /** Whether there is a change this page has not drawn yet */
    get behind() {
      return behind
    },

    stop: forget
  }
}
