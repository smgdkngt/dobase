// A todo tool's page drawn from what the API gives (GET /tools/:id/todo as JSON),
// in the same words and classes as the page the server draws (tools/todos/show): a
// trial of a tile that asks the API and draws itself (elements/dobase_todos.js).
// Text in, text out, so it is tried without a browser (test/javascript).

/**
 * @typedef {{ hue: string, second: string, pattern: number }} Look
 * @typedef {{ id: number, name: string }} Person
 * @typedef {{ url: string | null, initials: string, look: Look }} Avatar
 * @typedef {{
 *   id: number, title: string, due_date: string | null, completed: boolean, recurrence_rule: string | null,
 *   assignee: Person | null, assignee_avatar?: Avatar, comments_count: number, attachments_count: number, has_description?: boolean
 * }} Item
 * @typedef {{ id: number, title: string, description?: string | null, earlier_completed_count?: number, items: Item[] }} List
 * @typedef {{ tool: { id: number, name: string }, lists: List[] }} Todos
 * @typedef {{ today: string, adding?: number | null, earlier?: Record<string, Item[]> }} Now
 */

/** @type {Record<string, string>} */
const ICONS = {
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
  "check-circle": '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/>',
  "align-left": '<line x1="21" x2="3" y1="6" y2="6"/><line x1="15" x2="3" y1="12" y2="12"/><line x1="17" x2="3" y1="18" y2="18"/>',
  "message-square-text": '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M13 8H7"/><path d="M17 12H7"/>',
  paperclip: '<path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"/>',
  repeat: '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
  calendar: '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
  "grip-vertical": '<circle cx="9" cy="12" r="1"/><circle cx="9" cy="5" r="1"/><circle cx="9" cy="19" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="15" cy="5" r="1"/><circle cx="15" cy="19" r="1"/>'
}
/** @type {Record<string, string>} */
const REPEATS = { daily: "Daily", weekly: "Weekly", monthly: "Monthly" }
const MONTHS = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]
const DAY = 24 * 60 * 60 * 1000

/**
 * @param {Todos} todos
 * @param {Now} now today's date ("2030-01-16"), the list a todo is being added to, and the todos completed earlier that were asked for
 * @returns {string}
 */
export function todosPage(todos, now) {
  const lists = todos.lists.length
    ? `<div class="max-w-4xl mx-auto"><div class="flex flex-col gap-4">${todos.lists.map((list) => listOf(list, now)).join("")}</div></div>`
    : `<div class="flex items-center justify-center h-full"><p class="text-sm text-text-tertiary">Nothing to do yet</p></div>`

  return `
    <div class="tool-layout flex flex-col h-screen overflow-hidden">
      <div class="tool-topbar">
        <div class="flex items-center gap-2 flex-1 min-w-0"><h1 class="tool-topbar-title">${h(todos.tool.name)}</h1></div>
        <div class="tool-topbar-actions"></div>
      </div>
      <div class="tool-scroll-area flex-1 overflow-y-auto p-4 pt-6">${lists}</div>
    </div>`
}

/**
 * "Jan 20", with the year when it is another one: FormattingHelper#format_date
 * @param {string} date
 * @param {string} today
 * @returns {string}
 */
export function formatDate(date, today) {
  const [ year, month, day ] = date.split("-").map(Number)
  const short = `${MONTHS[month - 1]} ${day}`
  return year === Number(today.slice(0, 4)) ? short : `${short}, ${year}`
}

/**
 * How pressing a date is: past it, within two days of it, or neither
 * @param {string} date
 * @param {string} today
 * @returns {"late" | "soon" | "later"}
 */
export function urgency(date, today) {
  const days = Math.round((Date.parse(date) - Date.parse(today)) / DAY)
  return days < 0 ? "late" : days <= 2 ? "soon" : "later"
}

/** @type {(list: List, now: Now) => string} */
function listOf(list, now) {
  const open = list.items.filter((item) => !item.completed)
  const done = list.items.filter((item) => item.completed)
  const earlier = now.earlier?.[list.id]
  const count = list.earlier_completed_count || 0
  const adding = now.adding === list.id

  return `
    <div class="border border-border rounded-lg" id="todo-list-${list.id}" data-list-id="${list.id}">
      <div class="flex items-center justify-between py-3 px-4 gap-2">
        <span class="text-base font-semibold text-text-primary cursor-pointer px-1.5 py-0.5 rounded-sm border border-transparent flex-1 min-w-0 hover:bg-background-tertiary">${h(list.title)}</span>
        <span class="text-xs text-text-tertiary bg-background-tertiary rounded-full px-2 py-0.5 min-w-[1.25rem] text-center">${open.length}</span>
      </div>
      ${list.description ? `<div class="px-4 pb-2 text-sm text-text-secondary">${h(list.description)}</div>` : ""}
      <div class="todo-list-items px-2 pb-2 flex flex-col gap-0.5 min-h-[2rem] rounded-md transition-colors">
        ${[ ...open, ...done ].map(itemOf(now)).join("")}
        ${count > 0 ? `
          <button type="button" class="flex items-center gap-1.5 px-2 py-1.5 text-xs text-text-tertiary hover:text-text-primary transition-colors"
                  data-do="earlier" data-list-id="${list.id}" data-arrow-keys-target="item" aria-expanded="${Boolean(earlier)}">
            ${icon("check-circle", 12)}
            <span>${earlier ? `Hide ${count} completed` : `${count} completed`}</span>
          </button>
          ${earlier ? `<div class="flex flex-col gap-0.5">${earlier.map(itemOf(now)).join("")}</div>` : ""}` : ""}
      </div>
      <div class="todo-add-item px-2 pb-2">
        ${adding ? `
          <form class="flex flex-col gap-2" data-do="add" data-list-id="${list.id}">
            <textarea name="title" aria-label="Todo title" rows="1" placeholder="What needs to be done?" data-add-title
                      class="w-full px-2.5 py-2 border border-border rounded-md text-sm bg-surface text-text-primary outline-none resize-none focus:border-accent focus:ring-2 focus:ring-accent/15"></textarea>
            <div class="flex items-center gap-1.5">
              <button class="btn btn-primary btn-sm">Add</button>
              <button type="button" class="btn btn-ghost btn-sm" data-do="cancel">Cancel</button>
            </div>
          </form>` : `
          <button type="button" class="flex items-center gap-1.5 w-full px-2 py-1.5 rounded-md border-none bg-transparent text-text-tertiary text-sm cursor-pointer transition-all hover:bg-background-tertiary hover:text-text-primary"
                  data-do="adding" data-list-id="${list.id}" data-arrow-keys-target="item">
            ${icon("plus", 14)}
            Add item
          </button>`}
      </div>
    </div>`
}

/** @type {(now: Now) => (item: Item) => string} */
function itemOf(now) {
  return (item) => {
    const marks = [
      item.has_description ? icon("align-left", 12) : "",
      item.comments_count > 0 ? counted("message-square-text", item.comments_count) : "",
      item.attachments_count > 0 ? counted("paperclip", item.attachments_count) : "",
      item.recurrence_rule ? `<span class="inline-flex items-center" title="${h(REPEATS[item.recurrence_rule] || "")}">${icon("repeat", 12)}</span>` : ""
    ].join("")
    const due = { late: "text-error bg-error-light", soon: "text-warning bg-warning-light", later: "text-text-tertiary bg-background-tertiary" }

    return `
      <div class="todo-item flex items-center gap-3 px-2 py-2 rounded-md hover:bg-background-tertiary/50 transition-colors group ${item.completed ? "todo-item-completed" : ""}"
           id="todo-item-${item.id}" data-item-id="${item.id}">
        <div class="todo-checkbox-wrapper" data-checkbox-wrapper>
          <input type="checkbox" class="todo-checkbox" id="todo-item-${item.id}-completion" data-do="tick" data-item-id="${item.id}"
                 data-arrow-keys-target="item" aria-label="Mark &quot;${h(item.title)}&quot; complete" ${item.completed ? "checked" : ""}>
        </div>
        <div class="flex-1 min-w-0 flex items-center gap-2">
          <span class="text-[0.9375rem] text-text-primary leading-normal">${h(item.title)}</span>
          ${item.assignee ? `<span class="inline-flex shrink-0" role="img" title="Assigned to ${h(item.assignee.name)}" aria-label="Assigned to ${h(item.assignee.name)}">${face(item.assignee, item.assignee_avatar)}</span>` : ""}
          ${marks ? `<span class="inline-flex items-center gap-1.5 text-text-tertiary shrink-0">${marks}</span>` : ""}
        </div>
        ${item.due_date ? `
          <span class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded-sm shrink-0 ${due[urgency(item.due_date, now.today)]}">
            ${icon("calendar", 10)}
            ${formatDate(item.due_date, now.today)}
          </span>` : ""}
        <div class="todo-drag-handle" aria-hidden="true">${icon("grip-vertical", 14)}</div>
      </div>`
  }
}

/** @type {(person: Person, avatar?: Avatar) => string} */
function face(person, avatar) {
  if (avatar?.url) return `<div class="avatar avatar-xs"><img src="${h(avatar.url)}" alt="${h(person.name)}" class="w-full h-full object-cover"></div>`

  const look = avatar?.look
  const worn = look ? ` data-avatar-hue="${h(look.hue)}" data-avatar-second="${h(look.second)}" data-avatar-pattern="${h(look.pattern)}"` : ""
  return `<div class="avatar avatar-xs"${worn}><span>${h(avatar?.initials || "?")}</span></div>`
}

/** @type {(name: string, count: number) => string} */
function counted(name, count) {
  return `<span class="inline-flex items-center gap-0.5">${icon(name, 12)}<span class="text-xs">${count}</span></span>`
}

/** @type {(name: string, size: number) => string} */
function icon(name, size) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="shrink-0 " aria-hidden="true">${ICONS[name]}</svg>`
}

// Text as it stands in a page, whatever is in it
/** @type {(text: unknown) => string} */
function h(text) {
  return String(text ?? "").replace(/[&<>"']/g, (sign) => `&#${sign.charCodeAt(0)};`)
}
