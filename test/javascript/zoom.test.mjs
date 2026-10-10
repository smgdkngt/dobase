import { test } from "node:test"
import assert from "node:assert/strict"
import { within, stepIn, stepOut, wheelFactor, scrollToKeep, percent } from "services/zoom"

const picture = { min: 1, max: 8 }
const text = { min: 0.5, max: 4 }

test("the buttons go up from fit a step at a time, and stop at the most", () => {
  const steps = []
  for (let zoom = 1, last = 0; zoom !== last; last = zoom, zoom = stepIn(zoom, picture)) steps.push(zoom)

  assert.deepEqual(steps, [1, 1.25, 1.5, 2, 3, 4, 6, 8])
  assert.equal(stepIn(8, picture), 8)
})

test("and back down the same way, to fit for a picture and to half for text", () => {
  assert.equal(stepOut(2, picture), 1.5)
  assert.equal(stepOut(1.25, picture), 1)
  assert.equal(stepOut(1, picture), 1)
  assert.equal(stepOut(1, text), 0.8)
  assert.equal(stepOut(0.67, text), 0.5)
  assert.equal(stepOut(0.5, text), 0.5)
  assert.equal(stepIn(4, text), 4)
})

test("from where a pinch left it, the buttons go to the nearest step on that side", () => {
  assert.equal(stepIn(1.7, picture), 2)
  assert.equal(stepOut(1.7, picture), 1.5)
  assert.equal(stepOut(1.1, picture), 1)
})

test("a zoom is held between the least and the most", () => {
  assert.equal(within(0.3, picture), 1)
  assert.equal(within(0.3, text), 0.5)
  assert.equal(within(20, picture), 8)
  assert.equal(within(20, text), 4)
  assert.equal(within(2.37, picture), 2.37)
})

test("about fit is fit, and what is no number too", () => {
  assert.equal(within(1.03, picture), 1)
  assert.equal(within(0.97, text), 1)
  assert.equal(within(1.05, picture), 1.05)
  assert.equal(within(NaN, picture), 1)
  assert.equal(within(Infinity, picture), 1)
})

test("the wheel away from you zooms in, towards you out, and as much back", () => {
  assert.ok(wheelFactor(-4) > 1)
  assert.ok(wheelFactor(4) < 1)
  assert.ok(Math.abs(wheelFactor(-4) * wheelFactor(4) - 1) < 1e-9)
  assert.equal(wheelFactor(0), 1)
})

test("a notch of a mouse's wheel is about a third, however the browser counts it", () => {
  const notch = wheelFactor(-100)

  assert.ok(notch > 1.3 && notch < 1.4)
  assert.equal(wheelFactor(-3, 1), notch)
  assert.equal(wheelFactor(-1, 2), notch)
  assert.equal(wheelFactor(-1000), notch)
})

test("what was under the pointer stays under it", () => {
  // A picture that began at 100 on the screen, the pointer at 300, zoomed to twice
  // its size and drawn from 100 again: the point is now at 500, so 200 further on
  assert.equal(scrollToKeep(100, 100, 300, 2), 200)
  // Scrolled by that, it begins at -100 and nothing is left to do
  assert.equal(scrollToKeep(100, -100, 300, 2), 0)
  // Out again from there: back by as much
  assert.equal(scrollToKeep(-100, -100, 300, 0.5), -200)
  // The pointer on the edge it begins at needs nothing
  assert.equal(scrollToKeep(100, 100, 100, 3), 0)
})

test("a picture that came to stand elsewhere is counted from where it stands", () => {
  // In the middle while it fitted (from 200), from the left edge (16) once it is wider
  assert.equal(scrollToKeep(200, 16, 300, 4), 116)
})

test("how far it is zoomed reads as a percentage", () => {
  assert.equal(percent(1), "100%")
  assert.equal(percent(0.67), "67%")
  assert.equal(percent(2.374), "237%")
})
