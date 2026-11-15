import { test } from "node:test"
import assert from "node:assert/strict"
import { dismissLater } from "services/flash"

/**
 * A message on a page whose clock only moves when the test says so
 * @param {import("node:test").TestContext} t
 */
function message(t) {
  t.mock.timers.enable({ apis: [ "setTimeout" ] })
  const element = Object.assign(new EventTarget(), { contains: () => false })
  const state = { gone: false }
  dismissLater(/** @type {any} */ (element), 8000, () => { state.gone = true })
  return { element, state, wait: (/** @type {number} */ ms) => t.mock.timers.tick(ms) }
}

test("a message goes after its time", (t) => {
  const { state, wait } = message(t)

  wait(7999)
  assert.equal(state.gone, false)
  wait(1)
  assert.equal(state.gone, true)
})

test("a message stays while the pointer is on it, and its whole time after it left", (t) => {
  const { element, state, wait } = message(t)

  wait(5000)
  element.dispatchEvent(new Event("mouseenter"))
  wait(20000)
  assert.equal(state.gone, false)

  element.dispatchEvent(new Event("mouseleave"))
  wait(7999)
  assert.equal(state.gone, false)
  wait(1)
  assert.equal(state.gone, true)
})

test("a message stays while the keyboard is in it", (t) => {
  const { element, state, wait } = message(t)

  element.dispatchEvent(new Event("focusin"))
  wait(20000)
  assert.equal(state.gone, false)

  element.dispatchEvent(new Event("focusout"))
  wait(8000)
  assert.equal(state.gone, true)
})
