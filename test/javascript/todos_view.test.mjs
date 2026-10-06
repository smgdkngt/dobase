import { test } from "node:test"
import assert from "node:assert/strict"
import { todosPage, formatDate, urgency } from "services/todos_view"

/** @typedef {import("services/todos_view").Item} Item */

const TODAY = "2030-01-16"

/** @type {(with_?: Partial<Item>) => Item} */
const item = (with_ = {}) => ({ id: 1, title: "Buy groceries", due_date: null, completed: false, recurrence_rule: null, assignee: null, comments_count: 0, attachments_count: 0, ...with_ })

/** @type {(items: Item[], more?: object, now?: object) => string} */
const page = (items, more = {}, now = {}) => todosPage({ tool: { id: 7, name: "Launch Tasks" }, lists: [ { id: 3, title: "Before", items, ...more } ] }, { today: TODAY, ...now })

test("a date reads as the server writes it", () => {
  assert.equal(formatDate("2030-01-20", TODAY), "Jan 20")
  assert.equal(formatDate("2030-12-01", TODAY), "Dec 1")
  assert.equal(formatDate("2031-01-05", TODAY), "Jan 5, 2031")
})

test("a date is late once it is past, and soon within two days", () => {
  assert.equal(urgency("2030-01-15", TODAY), "late")
  assert.equal(urgency("2030-01-16", TODAY), "soon")
  assert.equal(urgency("2030-01-18", TODAY), "soon")
  assert.equal(urgency("2030-01-19", TODAY), "later")
})

test("the page is the tool's name over its lists, each with what is still to do", () => {
  const drawn = page([ item(), item({ id: 2, title: "Call dentist" }), item({ id: 3, title: "Send report", completed: true }) ])

  assert.match(drawn, /<h1 class="tool-topbar-title">Launch Tasks<\/h1>/)
  assert.match(drawn, />Before<\/span>\s*<span[^>]*>2<\/span>/)
  assert.ok(drawn.indexOf("Call dentist") < drawn.indexOf("Send report"), "What is done comes after what isn't")
  assert.match(drawn, /todo-item-completed"\s+id="todo-item-3"/)
  assert.match(drawn, /id="todo-item-3-completion"[^>]*checked/)
})

test("a todo shows who it is for, when it is due and what it has", () => {
  const drawn = page([ item({
    due_date: "2030-01-15", recurrence_rule: "weekly", comments_count: 2, has_description: true,
    assignee: { id: 4, name: "Marcus Rivera" }, assignee_avatar: { url: null, initials: "MR", look: { hue: "pink", second: "green", pattern: 3 } }
  }) ])

  assert.match(drawn, /title="Assigned to Marcus Rivera"/)
  assert.match(drawn, /data-avatar-hue="pink" data-avatar-second="green" data-avatar-pattern="3"><span>MR<\/span>/)
  assert.match(drawn, /text-error bg-error-light">[\s\S]*Jan 15/)
  assert.match(drawn, /title="Weekly"/)
  assert.match(drawn, /<span class="text-xs">2<\/span>/)
})

test("what someone typed is text, never a part of the page", () => {
  const drawn = page([ item({ title: `<img src=x onerror="alert(1)">` }) ], { title: "<b>Before</b>" })

  assert.doesNotMatch(drawn, /<img src=x/)
  assert.doesNotMatch(drawn, /<b>Before/)
  assert.match(drawn, /&#60;img src=x onerror=&#34;alert\(1\)&#34;&#62;/)
})

test("the todos completed earlier are a count until they are asked for", () => {
  const closed = page([ item() ], { earlier_completed_count: 2 })
  const open = page([ item() ], { earlier_completed_count: 2 }, { earlier: { 3: [ item({ id: 9, title: "Fix bug", completed: true }) ] } })

  assert.match(closed, /aria-expanded="false"[\s\S]*<span>2 completed<\/span>/)
  assert.doesNotMatch(closed, /Fix bug/)
  assert.match(open, /aria-expanded="true"[\s\S]*<span>Hide 2 completed<\/span>/)
  assert.match(open, /Fix bug/)
})

test("the list a todo is being added to has the field, the others the button", () => {
  assert.match(page([]), /data-do="adding" data-list-id="3"/)
  assert.doesNotMatch(page([]), /<textarea/)
  assert.match(page([], {}, { adding: 3 }), /<form[^>]*data-do="add" data-list-id="3">\s*<textarea name="title"/)
})

test("a tool without lists says so", () => {
  assert.match(todosPage({ tool: { id: 7, name: "Empty" }, lists: [] }, { today: TODAY }), /Nothing to do yet/)
})
