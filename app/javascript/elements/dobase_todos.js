import { api } from "services/api"
import { play } from "services/sound"
import { toolIdOf } from "services/tool_frame"
import { todosPage } from "services/todos_view"

// <dobase-todos src="/tools/12/todo">: a todo tool as a tile that asks the API for
// what there is and draws it itself (services/todos_view.js). A trial, beside the
// tile that is the server's page in a frame: /workspace?in-page=todos:api.
//
// It answers to what the workspace asks of a tile that is part of its page
// (services/tool_frame.js): `src`, `complete` once it is drawn, reload(). What is in
// it is marked as a tile's page, so the keys and the focus work as in any tile
// (tile_frame_controller.js, arrow_keys_controller.js).
//
// Drawn so far: the lists, their todos, ticking one off, adding one, and the ones
// completed earlier. Not: a todo's details, the filter by assignee, reordering.
class DobaseTodos extends HTMLElement {
  static observedAttributes = [ "src" ]

  connectedCallback() {
    this.classList.add("tile-frame")
    /** @type {{ adding: number | null, earlier: Record<string, any[]> }} */
    this.now = { adding: null, earlier: {} }
    this.addEventListener("click", (event) => this.pressed(event))
    this.addEventListener("change", (event) => this.pressed(event))
    this.addEventListener("submit", (event) => this.add(event))
    this.addEventListener("keydown", (event) => this.keyed(event))
    this.load()
  }

  attributeChangedCallback() {
    if (this.isConnected && this.now) this.load()
  }

  get address() {
    return `/tools/${toolIdOf(this.getAttribute("src"))}/todo`
  }

  reload() {
    return this.load()
  }

  async load() {
    const todos = await api(this.address)
    // Signed out, or a tool that is gone: the workspace finds out which
    if (!todos?.lists) return void this.dispatchEvent(new CustomEvent("tile:message", { bubbles: true, detail: { tile: "gone" } }))

    this.todos = todos
    this.draw()
    this.setAttribute("complete", "")
  }

  draw() {
    const today = new Date()
    const page = document.createElement("div")
    page.className = "tile-page"
    page.tabIndex = -1
    page.dataset.controller = "arrow-keys tile-frame"
    page.dataset.arrowKeysMainValue = "true"
    page.dataset.tileFrameTitleValue = this.todos.tool.name
    page.innerHTML = todosPage(this.todos, { ...this.now, today: [ today.getFullYear(), today.getMonth() + 1, today.getDate() ].map((part) => String(part).padStart(2, "0")).join("-") })

    // Laid over what is there, so the keyboard stays where it is and a tick keeps its burst
    this.firstElementChild ? Turbo.morphElements(this.firstElementChild, page) : this.append(page)
    this.querySelector("[data-add-title]")?.focus()
  }

  pressed(event) {
    const on = event.target.closest("[data-do]")
    if (!on || (event.type === "change") !== (on.dataset.do === "tick")) return

    const list = Number(on.dataset.listId)
    switch (on.dataset.do) {
      case "tick": return this.tick(on)
      case "adding": this.now.adding = list; break
      case "cancel": this.now.adding = null; break
      case "earlier": return this.earlier(list)
      default: return
    }
    this.draw()
  }

  async tick(box) {
    if (box.checked) {
      play("done")
      const around = box.closest("[data-checkbox-wrapper]")
      around.classList.add("completing")
      around.addEventListener("animationend", () => around.classList.remove("completing"), { once: true })
    }

    const done = await api(`${this.address}/items/${box.dataset.itemId}/completion`, box.checked ? "POST" : "DELETE")
    done ? this.load() : (box.checked = !box.checked)
  }

  async add(event) {
    event.preventDefault()
    const form = event.target
    const title = form.elements.title.value.trim()
    if (!title) return

    const added = await api(`/todo_lists/${form.dataset.listId}/items`, "POST", { item: { title } })
    if (!added) return

    this.now.adding = null
    this.load()
  }

  // The todos completed more than a day ago are asked for when someone wants them
  async earlier(list) {
    if (this.now.earlier[list]) {
      delete this.now.earlier[list]
    } else {
      const all = await api(`${this.address}?completed=true`)
      const now = (all?.lists.find((one) => one.id === list)?.items || [])
      const shown = new Set(this.todos.lists.find((one) => one.id === list)?.items.map((item) => item.id))
      this.now.earlier[list] = now.filter((item) => !shown.has(item.id))
    }
    this.draw()
  }

  keyed(event) {
    if (!event.target.matches("[data-add-title]")) return

    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
    } else if (event.key === "Escape") {
      event.stopPropagation()
      this.now.adding = null
      this.draw()
    }
  }
}

customElements.define("dobase-todos", DobaseTodos)
