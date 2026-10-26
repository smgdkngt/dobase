import { test } from "node:test"
import assert from "node:assert/strict"
import { closes, pullsDown, CLOSING_DISTANCE } from "services/sheet"

test("a long pull closes the sheet, however slow", () => {
  assert.equal(closes(CLOSING_DISTANCE, 2000), true)
  assert.equal(closes(CLOSING_DISTANCE - 1, 2000), false)
})

test("a short quick flick closes it, a tiny one doesn't", () => {
  assert.equal(closes(40, 50), true)
  assert.equal(closes(10, 5), false)
  assert.equal(closes(40, 400), false)
})

test("a pull up never closes it", () => {
  assert.equal(closes(-200, 50), false)
  assert.equal(closes(0, 0), false)
})

test("only a move that is mostly down is a pull", () => {
  assert.equal(pullsDown(10, 2), true)
  assert.equal(pullsDown(10, 20), false)
  assert.equal(pullsDown(-10, 0), false)
})
