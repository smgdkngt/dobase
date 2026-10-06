import { test } from "node:test"
import assert from "node:assert/strict"
import { pathOf, toolIdOf } from "services/tool_frame"

test("the path of an address on this site", () => {
  assert.equal(pathOf("/tools/12/board?card=3#comments"), "/tools/12/board?card=3#comments")
  assert.equal(pathOf("https://dobase.test/tools/12/board"), "/tools/12/board")
  assert.equal(pathOf("tools/12"), "/tools/12")
})

test("no path from an address anywhere else", () => {
  assert.equal(pathOf("https://elsewhere.example/tools/12"), null)
  assert.equal(pathOf("//elsewhere.example/tools/12"), null)
  assert.equal(pathOf("javascript:alert(1)"), null)
  assert.equal(pathOf("http://dobase.test/tools/12"), null)
})

test("no path that a frame would read as another site", () => {
  assert.equal(pathOf("/.//elsewhere.example"), null)
  assert.equal(pathOf("https://dobase.test//elsewhere.example"), null)
})

test("no path from nothing", () => {
  assert.equal(pathOf(null), null)
  assert.equal(pathOf(""), null)
  assert.equal(pathOf(undefined), null)
})

test("the tool a path is a page of", () => {
  assert.equal(toolIdOf("/tools/12/board?card=3"), "12")
  assert.equal(toolIdOf("/tools/12"), "12")
  assert.equal(toolIdOf("/tools/new"), null)
  assert.equal(toolIdOf("/cards/12"), null)
  assert.equal(toolIdOf("/elsewhere/tools/12"), null)
  assert.equal(toolIdOf(null), null)
})
