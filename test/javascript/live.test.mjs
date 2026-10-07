import { test } from "node:test"
import assert from "node:assert/strict"
import { refresher, SETTLE_MS, REST_MS, RETRY_MS } from "services/live"

/**
 * A page with a clock that only moves when the test says so
 * @param {import("node:test").TestContext} t
 * @param {{ busy?: boolean }} [page]
 */
function page(t, { busy = false } = {}) {
  t.mock.timers.enable({ apis: [ "setTimeout", "Date" ] })
  const state = { drawn: 0, busy }
  const live = refresher({ draw: () => { state.drawn += 1 }, busy: () => state.busy })
  return { state, live, wait: (/** @type {number} */ ms) => t.mock.timers.tick(ms) }
}

test("a change is drawn a moment later, not at once", (t) => {
  const { state, live, wait } = page(t)

  live.changed()
  assert.equal(state.drawn, 0)
  assert.equal(live.behind, true)

  wait(SETTLE_MS)
  assert.equal(state.drawn, 1)
  assert.equal(live.behind, false)
})

test("changes that come together are drawn once", (t) => {
  const { state, live, wait } = page(t)

  for (let made = 0; made < 20; made++) {
    live.changed()
    wait(10)
  }
  wait(SETTLE_MS)

  assert.equal(state.drawn, 1)
})

test("a row of changes that goes on is drawn now and then, and at its end", (t) => {
  const { state, live, wait } = page(t)

  // One every 200 ms for 6 seconds
  for (let made = 0; made < 30; made++) {
    live.changed()
    wait(200)
  }
  wait(REST_MS)

  assert.equal(live.behind, false)
  assert.ok(state.drawn >= 3, `drawn ${state.drawn} times`)
  assert.ok(state.drawn <= 6000 / REST_MS + 2, `drawn ${state.drawn} times`)
})

test("a page that is busy stays as it is, and draws once it is free", (t) => {
  const { state, live, wait } = page(t, { busy: true })

  live.changed()
  wait(SETTLE_MS + RETRY_MS * 5)
  assert.equal(state.drawn, 0)
  assert.equal(live.behind, true)

  state.busy = false
  wait(RETRY_MS)
  assert.equal(state.drawn, 1)
  assert.equal(live.behind, false)
})

test("a page that is looked at again doesn't wait for its next look", (t) => {
  const { state, live, wait } = page(t, { busy: true })

  live.changed()
  wait(SETTLE_MS + 1)
  state.busy = false
  live.look()
  wait(0)

  assert.equal(state.drawn, 1)
})

test("looking at a page that is not behind draws nothing", (t) => {
  const { state, live, wait } = page(t)

  live.look()
  wait(REST_MS * 2)

  assert.equal(state.drawn, 0)
})

test("two drawings are never closer than the rest between them", (t) => {
  const { state, live, wait } = page(t)

  live.changed()
  wait(SETTLE_MS)
  assert.equal(state.drawn, 1)

  live.changed()
  live.look()
  wait(REST_MS - 1)
  assert.equal(state.drawn, 1)

  wait(1)
  assert.equal(state.drawn, 2)
})

test("a page that is gone draws nothing more", (t) => {
  const { state, live, wait } = page(t)

  live.changed()
  live.stop()
  wait(REST_MS * 2)

  assert.equal(state.drawn, 0)
})
