import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { addAgainLater, forgetAddAgain, takeAddAgain, WAIT_MS } from "services/add_again"

beforeEach(() => forgetAddAgain())

test("the page drawn after adding opens the same column's field again, once", () => {
  addAgainLater("board-4", "12", 1000)

  assert.equal(takeAddAgain("board-4", 1200), "12")
  assert.equal(takeAddAgain("board-4", 1300), null)
})

test("another page doesn't take it", () => {
  addAgainLater("board-4", "12", 1000)

  assert.equal(takeAddAgain("todos-9", 1200), null)
  assert.equal(takeAddAgain("board-4", 1200), "12")
})

test("a drawing long after the add opens nothing", () => {
  addAgainLater("todos-9", "3", 1000)

  assert.equal(takeAddAgain("todos-9", 1000 + WAIT_MS + 1), null)
})

test("an add that didn't go through is forgotten", () => {
  addAgainLater("todos-9", "3", 1000)
  forgetAddAgain()

  assert.equal(takeAddAgain("todos-9", 1100), null)
})
