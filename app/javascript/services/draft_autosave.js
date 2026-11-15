// What the compose form saves by itself, and when (compose_controller.js). The form is
// compared as a snapshot: a string of what it would save.

// A pause in the writing this long saves the draft
export const AUTOSAVE_DELAY = 3000
// A save that didn't go through is tried again after this long, while nothing else is typed
export const RETRY_DELAY = 15000
// Send (or Save Draft) pressed while a save is on its way waits for that save this long
// at most: a save that hangs (a server that doesn't answer) never holds the mail back
export const SEND_WAIT = 3000
// A request that outlives its page (keepalive) may carry this much at most, all of them
// together; under it, with room for the multipart boundaries
const KEEPALIVE_LIMIT = 60000

/**
 * Whether the form holds something its draft doesn't.
 * @param {object} form
 * @param {string | null} form.current what the form holds now
 * @param {string | null} form.untouched what it held when someone first reached for it, null before that
 * @param {string | null} form.saved what was last saved from it, null before the first save
 * @param {boolean} [form.unsent] a form that came back from a failed send: its message is saved nowhere
 * @returns {boolean}
 */
export function hasUnsaved({ current, untouched, saved, unsent = false }) {
  if (saved !== null) return current !== saved
  if (unsent) return true
  // What a reply, forward or draft starts with isn't a change, and a form nobody reached
  // for has none
  return untouched !== null && current !== untouched
}

/**
 * Whether a request with this body can be sent so that it goes on after its page is gone
 * @param {Iterable<[string, string | File]>} entries
 * @returns {boolean}
 */
export function fitsKeepalive(entries) {
  const encoder = new TextEncoder()
  let size = 0
  for (const [name, value] of entries) {
    size += encoder.encode(name).length + (typeof value === "string" ? encoder.encode(value).length : value.size) + 100
    if (size > KEEPALIVE_LIMIT) return false
  }
  return true
}

/**
 * What the form says once its draft is saved: "Saved 12:04", in the reader's own way of
 * writing a time
 * @param {Date} date
 * @param {string | string[]} [locales]
 * @returns {string}
 */
export function savedAt(date, locales) {
  return `Saved ${date.toLocaleTimeString(locales, { hour: "numeric", minute: "2-digit" })}`
}

/**
 * Whether the promise settles, either way, within this many milliseconds
 * @param {Promise<unknown>} promise
 * @param {number} ms
 * @returns {Promise<boolean>}
 */
export function settlesWithin(promise, ms) {
  return new Promise(resolve => {
    const timer = setTimeout(() => resolve(false), ms)
    const settled = () => { clearTimeout(timer); resolve(true) }
    promise.then(settled, settled)
  })
}
