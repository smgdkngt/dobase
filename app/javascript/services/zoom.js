// How far a file is zoomed in where it is shown (zoom_controller.js). 1 is the file as
// it fits; the rest is counted from there. Nothing here knows about a page.

// Where the buttons and the keys go: from fit up to eight times, and down to half
const STEPS = [0.5, 0.67, 0.8, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

// Nearer to fit than this is fit: a pinch that ends about where it began ends there
const NEAR_FIT = 0.04

/**
 * @typedef {{ min: number, max: number }} Limits
 */

/**
 * A zoom someone asked for, as far as it goes
 * @param {number} zoom
 * @param {Limits} limits
 * @returns {number}
 */
export function within(zoom, { min, max }) {
  if (!Number.isFinite(zoom)) return 1
  if (Math.abs(zoom - 1) < NEAR_FIT) return 1

  return Math.min(max, Math.max(min, zoom))
}

/**
 * The next step in, which is where it is when there is none
 * @param {number} zoom
 * @param {Limits} limits
 * @returns {number}
 */
export function stepIn(zoom, limits) {
  const next = STEPS.find((step) => step > zoom + 0.001)
  return within(next ?? zoom, limits)
}

/**
 * @param {number} zoom
 * @param {Limits} limits
 * @returns {number}
 */
export function stepOut(zoom, limits) {
  const next = STEPS.findLast((step) => step < zoom - 0.001)
  return within(next ?? zoom, limits)
}

/**
 * What a turn of the wheel multiplies the zoom by. A pinch on a trackpad comes as a
 * wheel too, a few pixels at a time; a mouse's wheel says a hundred a notch, or three
 * lines, and is held to about a third.
 * @param {number} delta the wheel's deltaY
 * @param {number} mode its deltaMode: pixels, lines or pages
 * @returns {number}
 */
export function wheelFactor(delta, mode = 0) {
  const pixels = delta * (mode === 1 ? 16 : mode === 2 ? 100 : 1)
  return Math.exp(-Math.max(-30, Math.min(30, pixels)) / 100)
}

/**
 * How far to scroll on so that what was under a point is under it again, on one axis.
 * Everything is a place on the screen.
 * @param {number} before where what is shown began before the zoom changed
 * @param {number} after where it begins now
 * @param {number} at the point to keep: the pointer, the middle of two fingers
 * @param {number} ratio the new zoom over the old
 * @returns {number}
 */
export function scrollToKeep(before, after, at, ratio) {
  return after + (at - before) * ratio - at
}

/**
 * @param {number} zoom
 * @returns {string} "125%"
 */
export function percent(zoom) {
  return `${Math.round(zoom * 100)}%`
}
