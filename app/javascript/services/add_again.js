// After a card or a todo is added, its page is drawn again (the answer is the page
// itself), which closes the field it was typed in, so a second one took another click.
// The page notes where it was adding as the form goes; whichever drawing comes next
// (a morph, a new page, a tile's frame) opens that field again with the cursor in it.
// A module's state outlives the controllers a drawing may replace.

export const WAIT_MS = 10_000

/** @type {{ scope: string, id: string, at: number } | null} */
let pending = null

/**
 * A card or todo is on its way from this field
 * @param {string} scope the page ("board-4")
 * @param {string} id the column or list it is added to
 * @param {number} [now]
 */
export function addAgainLater(scope, id, now = Date.now()) {
  pending = { scope, id, at: now }
}

/** It didn't go through: the field is still open as it was */
export function forgetAddAgain() {
  pending = null
}

/**
 * The column or list to open the field of again on this page, once
 * @param {string} scope
 * @param {number} [now]
 * @returns {string | null}
 */
export function takeAddAgain(scope, now = Date.now()) {
  if (!pending || pending.scope !== scope) return null

  const { id, at } = pending
  pending = null
  return now - at <= WAIT_MS ? id : null
}
