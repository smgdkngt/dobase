import { test } from "node:test"
import assert from "node:assert/strict"
import { hasUnsaved, fitsKeepalive, savedAt } from "services/draft_autosave"

test("a form nobody reached for has nothing to save", () => {
  assert.equal(hasUnsaved({ current: "a", untouched: null, saved: null }), false)
})

test("a reply as it started, with its signature and quote, has nothing to save", () => {
  assert.equal(hasUnsaved({ current: "sig", untouched: "sig", saved: null }), false)
})

test("a change since the form was reached for is unsaved until it is saved", () => {
  assert.equal(hasUnsaved({ current: "sig hi", untouched: "sig", saved: null }), true)
  assert.equal(hasUnsaved({ current: "sig hi", untouched: "sig", saved: "sig hi" }), false)
  assert.equal(hasUnsaved({ current: "sig hi!", untouched: "sig", saved: "sig hi" }), true)
})

test("written back to what it started as after a save, it is unsaved again", () => {
  assert.equal(hasUnsaved({ current: "sig", untouched: "sig", saved: "sig hi" }), true)
})

test("a form back from a failed send is unsaved until it is saved", () => {
  assert.equal(hasUnsaved({ current: "hi", untouched: null, saved: null, unsent: true }), true)
  assert.equal(hasUnsaved({ current: "hi", untouched: null, saved: "hi", unsent: true }), false)
})

test("a short message can outlive its page, a long one can't", () => {
  assert.equal(fitsKeepalive([ [ "subject", "Plans" ], [ "body", "<p>Hi</p>" ] ]), true)
  assert.equal(fitsKeepalive([ [ "body", "é".repeat(40000) ] ]), false)
})

test("a save says when it was", () => {
  assert.equal(savedAt(new Date(2026, 10, 15, 12, 4), "en-GB"), "Saved 12:04")
  assert.match(savedAt(new Date(2026, 10, 15, 18, 5), "en-US"), /^Saved 6:05\sPM$/)
})
