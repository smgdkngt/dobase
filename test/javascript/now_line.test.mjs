import { test } from "node:test"
import assert from "node:assert/strict"
import { minutesIntoDay, nowLineTop } from "services/now_line"

test("the minutes since midnight are counted on the clock of the zone the page is in", () => {
  const moment = new Date("2026-11-15T13:30:00Z")

  assert.equal(minutesIntoDay(moment, "UTC"), 13 * 60 + 30)
  assert.equal(minutesIntoDay(moment, "Europe/Amsterdam"), 14 * 60 + 30)
  assert.equal(minutesIntoDay(moment, "America/New_York"), 8 * 60 + 30)
})

test("in summer too, and past midnight in a zone ahead of UTC", () => {
  assert.equal(minutesIntoDay(new Date("2026-07-01T13:30:00Z"), "Europe/Amsterdam"), 15 * 60 + 30)
  assert.equal(minutesIntoDay(new Date("2026-11-15T23:15:00Z"), "Europe/Amsterdam"), 15)
})

test("midnight is the top of the day, never its bottom", () => {
  assert.equal(minutesIntoDay(new Date("2026-11-15T23:00:00Z"), "Europe/Amsterdam"), 0)
})

test("a zone the browser doesn't know is the browser's own", () => {
  const moment = new Date("2026-11-15T13:30:00Z")

  assert.equal(minutesIntoDay(moment, "Mars/Olympus_Mons"), minutesIntoDay(moment, undefined))
})

test("the line lies that far down the day", () => {
  assert.equal(nowLineTop(0), "0%")
  assert.equal(nowLineTop(12 * 60), "50%")
  assert.equal(nowLineTop(18 * 60), "75%")
})
