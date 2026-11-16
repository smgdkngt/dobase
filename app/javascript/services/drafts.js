// What someone typed and hasn't sent yet (a comment, a description), kept in this tab
// under a name of its own ("card-12-comment") until it is sent or let go of. Closing a
// card's dialog then loses nothing: it is there again when the card opens again.
// Storage can be missing or refuse (a private window): then nothing is kept.

const PREFIX = "draft:"

/** @param {string} name @returns {string | null} what was kept, or null */
export function readDraft(name) {
  try {
    return window.sessionStorage.getItem(PREFIX + name)
  } catch {
    return null
  }
}

/**
 * Keeps what is typed, or lets go of it when it is what was there to begin with.
 * @param {string} name
 * @param {string} text
 * @param {string} initial
 */
export function keepDraft(name, text, initial) {
  if (text === initial) return dropDraft(name)

  try {
    window.sessionStorage.setItem(PREFIX + name, text)
  } catch {
    // nothing kept
  }
}

/** @param {string} name */
export function dropDraft(name) {
  try {
    window.sessionStorage.removeItem(PREFIX + name)
  } catch {
    // nothing to let go of
  }
}
