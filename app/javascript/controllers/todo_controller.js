import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

export default class extends Controller {
  static targets = ["itemModal", "itemDetailDialog", "addItemForm", "addItemInput", "addItemBtn", "completedSection", "completedToggle", "completedToggleLabel"]
  static values = { toolId: String }

  // ── Item detail modal ──

  connect() {
    if (this.hasItemDetailDialogTarget) {
      this._onModalClose = () => {
        const url = new URL(window.location.href)
        url.searchParams.delete("item")
        Turbo.visit(url.toString(), { action: "replace" })
      }
      this.itemDetailDialogTarget.addEventListener("close", this._onModalClose)

      // Auto-open item if ?item=ID is in the URL
      const itemId = new URL(window.location.href).searchParams.get("item")
      if (itemId) this.#openItemById(itemId)
    }
  }

  disconnect() {
    if (this.hasItemDetailDialogTarget && this._onModalClose) {
      this.itemDetailDialogTarget.removeEventListener("close", this._onModalClose)
    }
  }

  openItem(event) {
    const itemId = event.currentTarget.dataset.itemId
    this.#openItemById(itemId)
  }

  #openItemById(itemId) {
    const url = `/tools/${this.toolIdValue}/todo/items/${itemId}`

    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => response.text())
      .then(html => {
        if (this.hasItemModalTarget) {
          this.itemModalTarget.innerHTML = html
        }
        if (this.hasItemDetailDialogTarget) this.itemDetailDialogTarget.showModal()
      })
      .catch(error => {
        console.error("Error loading item:", error)
      })
  }

  // ── Checkbox toggle ──

  async toggleCompletion(event) {
    const checkbox = event.currentTarget
    const url = checkbox.dataset.completeUrl
    const method = checkbox.checked ? "POST" : "DELETE"

    // Play the completion burst animation before the network call
    if (checkbox.checked) {
      const wrapper = checkbox.closest("[data-checkbox-wrapper]")
      if (wrapper) {
        wrapper.classList.add("completing")
        wrapper.addEventListener("animationend", () => wrapper.classList.remove("completing"), { once: true })
      }
    }

    const result = await api(url, method)
    if (result) {
      Turbo.visit(window.location.href, { action: "replace" })
    } else {
      checkbox.checked = !checkbox.checked
    }
  }

  // ── List rename ──

  startRenameList(event) {
    const span = event.currentTarget
    const listId = span.dataset.listId
    const currentName = span.textContent.trim()

    const input = document.createElement("input")
    input.type = "text"
    input.value = currentName
    input.className = "todo-list-name-input"

    const finishRename = async () => {
      const newName = input.value.trim()
      if (newName && newName !== currentName) {
        await api(`/tools/${this.toolIdValue}/todo/lists/${listId}`, "PATCH", { title: newName })
        span.textContent = newName
      }
      input.replaceWith(span)
    }

    input.addEventListener("blur", finishRename)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur() }
      if (e.key === "Escape") { input.value = currentName; input.blur() }
    })

    span.replaceWith(input)
    input.focus()
    input.select()
  }

  // ── Completed items toggle ──

  toggleCompleted(event) {
    const listId = event.currentTarget.dataset.listId
    const section = this.completedSectionTargets.find(s => s.dataset.listId === listId)
    const label = this.completedToggleLabelTargets.find(l => l.dataset.listId === listId)
    if (section) {
      const isHidden = !section.classList.contains("flex")
      section.classList.toggle("hidden", !isHidden)
      section.classList.toggle("flex", isHidden)
      if (label) {
        const count = label.textContent.match(/\d+/)?.[0] || ""
        label.textContent = isHidden ? `Hide ${count} completed` : `${count} completed`
      }
    }
  }

  // ── Add item form ──

  addItemToFirstList() {
    const firstBtn = this.addItemBtnTargets[0]
    if (firstBtn) firstBtn.click()
  }

  showAddItem(event) {
    const listId = event.currentTarget.dataset.listId
    const form = this.addItemFormTargets.find(f => f.dataset.listId === listId)
    const input = this.addItemInputTargets.find(i => i.dataset.listId === listId)
    if (form) {
      event.currentTarget.classList.add("hidden")
      form.classList.add("active")
      input?.focus()
    }
  }

  hideAddItem(event) {
    const listId = event.currentTarget.dataset.listId
    this._hideAddItemForm(listId)
  }

  addItemKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
    }
    if (event.key === "Escape") {
      this._hideAddItemForm(event.currentTarget.dataset.listId)
    }
  }

  // ── Private ──

  _hideAddItemForm(listId) {
    const form = this.addItemFormTargets.find(f => f.dataset.listId === listId)
    const input = this.addItemInputTargets.find(i => i.dataset.listId === listId)
    if (form) {
      form.classList.remove("active")
      if (input) input.value = ""
      const btn = this.addItemBtnTargets.find(b => b.dataset.listId === listId)
      if (btn) btn.classList.remove("hidden")
    }
  }
}
