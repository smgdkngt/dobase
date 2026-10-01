import { Controller } from "@hotwired/stimulus"
import { api, apiPatch, apiPost, apiDelete } from "services/api"

export default class extends Controller {
  static targets = ["groupContent", "editToolFrame", "editToolDialog", "nav"]

  connect() {
    this._preventReorderNav = (e) => {
      if (!this.element.classList.contains("reorder-mode")) return
      const link = e.target.closest("a")
      if (link) e.preventDefault()
    }
    this.navTarget.addEventListener("click", this._preventReorderNav)
  }

  disconnect() {
    this.navTarget.removeEventListener("click", this._preventReorderNav)
  }

  // ── Collapse/Expand ──

  toggleGroup(event) {
    if (event.target.closest("[data-sidebar-context-btn]")) return
    event.stopPropagation()
    const groupId = event.currentTarget.dataset.groupId
    const content = this.groupContentTargets.find(c => c.dataset.groupId === groupId)
    if (!content) return

    const isHidden = content.classList.contains("hidden")
    content.classList.toggle("hidden")

    const icon = event.currentTarget.querySelector("[data-sidebar-chevron] svg")
    icon?.classList.toggle("rotate-90", isHidden)

    apiPatch(`/sidebar_groups/${groupId}`, { collapsed: !isHidden })
  }

  // ── Rename ──

  startRename(event) {
    event.preventDefault()
    event.stopPropagation()
    this._beginRename(event.currentTarget, event.currentTarget.dataset.groupId)
  }

  renameFromMenu(event) {
    const groupId = event.currentTarget.dataset.groupId
    const nameEl = this.element.querySelector(`.sidebar-group-name[data-group-id="${groupId}"]`)
    if (nameEl) this._beginRename(nameEl, groupId)
  }

  _beginRename(span, groupId) {
    const currentName = span.textContent.trim()
    const input = document.createElement("input")
    input.type = "text"
    input.value = currentName
    input.className = "sidebar-rename-input"

    const finish = async () => {
      const newName = input.value.trim()
      if (newName && newName !== currentName) {
        await apiPatch(`/sidebar_groups/${groupId}`, { name: newName })
        span.textContent = newName
      } else {
        span.textContent = currentName
      }
      if (input.parentNode) input.replaceWith(span)
    }

    input.addEventListener("blur", finish)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur() }
      if (e.key === "Escape") { input.value = currentName; input.blur() }
    })

    span.replaceWith(input)
    input.focus()
    input.select()
  }

  // ── Tool Settings ──

  editTool(event) {
    event.stopPropagation()
    event.preventDefault()
    const toolId = event.currentTarget.dataset.toolId
    if (!toolId) return
    const frame = document.getElementById("edit-tool-form")
    const dialog = document.getElementById("edit-tool-modal")
    if (frame) frame.src = `/tools/${toolId}/edit`
    if (dialog) dialog.showModal()
  }

  // ── The tool beside ──

  // Opens a tool beside the one you have open, or closes it there. The pane lives
  // next to <body> (side_pane_controller.js), so it hears of it on the window.
  toggleBeside(event) {
    event.stopPropagation()
    event.preventDefault()
    window.dispatchEvent(new CustomEvent("side-pane:toggle", { detail: { url: event.currentTarget.dataset.url } }))
  }

  // ── Reorder Mode ──

  toggleReorder() {
    const active = this.element.classList.toggle("reorder-mode")

    // Toggle reorder-mode on each sortable container (shared > [data-sort-id] rule)
    // and enable/disable their sortable controllers
    this.navTarget.querySelectorAll("[data-controller~='sortable']").forEach(el => {
      el.classList.toggle("reorder-mode", active)
      const ctrl = this.application.getControllerForElementAndIdentifier(el, "sortable")
      if (ctrl) ctrl.enabledValue = active
    })
  }

  // ── Cross-container Tool Move ──

  // The sortable saves the new order once this is done: a tool has to be in its new group
  // before it can be given a place there, or it ends up last
  handleToolMove(event) {
    event.detail.waitUntil(this._moveTool(event.detail))
  }

  async _moveTool({ itemId, fromId, toId }) {
    if (fromId && fromId !== "ungrouped") {
      await apiDelete(`/sidebar_groups/${fromId}/memberships/${itemId}`)
    }
    if (toId && toId !== "ungrouped") {
      await apiPost(`/sidebar_groups/${toId}/memberships`, { tool_id: itemId })
    }
  }
}
