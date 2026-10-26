// A row swiped aside with a finger, as a phone's mail app has it: past a distance, or
// flicked, letting go does what the row offers (mail_swipe_controller.js).

/** How far a row is swiped before letting go of it does it */
export const DOING_DISTANCE = 96

/**
 * What a finger's first move is: a swipe sideways, a scroll, or not yet either
 * @param {number} sideways how far it went towards the start (left): positive
 * @param {number} down
 * @returns {"swipe" | "scroll" | null}
 */
export function gesture(sideways, down) {
  if (Math.abs(sideways) < 8 && Math.abs(down) < 8) return null
  return sideways > 0 && sideways > Math.abs(down) * 1.5 ? "swipe" : "scroll"
}

/**
 * Whether letting go here does what the row offers
 * @param {number} distance how far it was swiped towards the start
 * @param {number} milliseconds how long the swipe took
 * @returns {boolean}
 */
export function done(distance, milliseconds) {
  if (distance >= DOING_DISTANCE) return true
  return distance >= 40 && milliseconds > 0 && distance / milliseconds >= 0.6
}
