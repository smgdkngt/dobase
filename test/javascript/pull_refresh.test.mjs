import { test } from "node:test"
import assert from "node:assert/strict"
import { shown, refreshes, FURTHEST, REFRESHING_AT } from "services/pull_refresh"

test("the indicator follows the finger at half its distance, and no further than it goes", () => {
  assert.equal(shown(40), 20)
  assert.equal(shown(1000), FURTHEST)
  assert.equal(shown(-30), 0)
})

test("letting go refreshes once the indicator is far enough down", () => {
  assert.equal(refreshes(REFRESHING_AT), true)
  assert.equal(refreshes(REFRESHING_AT - 1), false)
  assert.equal(refreshes(shown(REFRESHING_AT * 2)), true)
})
