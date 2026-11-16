import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { readDraft, keepDraft, dropDraft } from "services/drafts"

/** @type {Map<string, string>} */
let stored

/** A tab's sessionStorage, or one that refuses everything (a private window) */
function storage({ refusing = false } = {}) {
  const refuse = () => { throw new Error("refused") }
  return {
    getItem: refusing ? refuse : (/** @type {string} */ key) => stored.get(key) ?? null,
    setItem: refusing ? refuse : (/** @type {string} */ key, /** @type {string} */ value) => { stored.set(key, value) },
    removeItem: refusing ? refuse : (/** @type {string} */ key) => { stored.delete(key) }
  }
}

beforeEach(() => {
  stored = new Map()
  Object.assign(globalThis, { window: { sessionStorage: storage() } })
})

test("what is typed is kept under its name and read back", () => {
  keepDraft("card-1-comment", "<p>Half a thought</p>", "")

  assert.equal(readDraft("card-1-comment"), "<p>Half a thought</p>")
  assert.equal(readDraft("card-2-comment"), null)
})

test("typing back what was there to begin with lets go of the draft", () => {
  keepDraft("card-1-description", "<p>Changed</p>", "<p>Was</p>")
  keepDraft("card-1-description", "<p>Was</p>", "<p>Was</p>")

  assert.equal(readDraft("card-1-description"), null)
})

test("a draft that is sent or cancelled is gone", () => {
  keepDraft("todo-3-comment", "<p>Soon</p>", "")
  dropDraft("todo-3-comment")

  assert.equal(readDraft("todo-3-comment"), null)
})

test("storage that refuses keeps nothing and breaks nothing", () => {
  Object.assign(globalThis, { window: { sessionStorage: storage({ refusing: true }) } })

  keepDraft("card-1-comment", "<p>Lost</p>", "")
  dropDraft("card-1-comment")
  assert.equal(readDraft("card-1-comment"), null)
})
