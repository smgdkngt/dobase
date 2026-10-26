import { test } from "node:test"
import assert from "node:assert/strict"
import { gesture, done, DOING_DISTANCE } from "services/swipe"

test("a first move that is too small is nothing yet", () => {
  assert.equal(gesture(3, 2), null)
})

test("mostly to the left is a swipe, anything else a scroll", () => {
  assert.equal(gesture(30, 5), "swipe")
  assert.equal(gesture(30, 25), "scroll")
  assert.equal(gesture(-30, 0), "scroll")
  assert.equal(gesture(0, 30), "scroll")
})

test("far enough, or a quick flick, does it", () => {
  assert.equal(done(DOING_DISTANCE, 1000), true)
  assert.equal(done(50, 60), true)
  assert.equal(done(50, 500), false)
  assert.equal(done(20, 10), false)
})
