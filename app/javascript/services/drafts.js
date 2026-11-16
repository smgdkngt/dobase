// What someone typed and hasn't sent yet (a comment, a description), kept in this tab
// under a name of its own ("u3-card-12-comment": whose, and where) until it is sent or let go of. Closing a
// card's dialog then loses nothing: it is there again when the card opens again.
// Storage can be missing or refuse (a private window): then nothing is kept.

const PREFIX = "draft:"

/**
 * What was kept, when it was typed over what is there now: a description someone
 * else changed meanwhile is theirs, and a draft of the one before is let go of
 * rather than put over it.
 * @param {string} name
 * @param {string} initial what the field holds now, as the server drew it
 * @returns {string | null} what was kept, or null
 */
export function readDraft(name, initial) {
  let kept
  try {
    kept = JSON.parse(window.sessionStorage.getItem(PREFIX + name) || "null")
  } catch {
    return null
  }
  if (!kept || typeof kept.text !== "string") return null
  if (kept.from !== initial) {
    dropDraft(name)
    return null
  }
  return kept.text
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
    window.sessionStorage.setItem(PREFIX + name, JSON.stringify({ text, from: initial }))
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
