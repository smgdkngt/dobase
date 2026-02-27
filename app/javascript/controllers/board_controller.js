import { Controller } from "@hotwired/stimulus"
import { api } from "services/api"

export default class extends Controller {
  static targets = ["cardModal", "cardDetailDialog", "addCardForm", "addCardInput", "addCardBtn", "archivedSection", "archivedToggle", "archivedToggleLabel"]
  static values = { toolId: String }

  // ── Card detail modal ──

  connect() {
    if (this.hasCardDetailDialogTarget) {
      this._onModalClose = () => {
        const url = new URL(window.location.href)
        url.searchParams.delete("card")
        Turbo.visit(url.toString(), { action: "replace" })
      }
      this.cardDetailDialogTarget.addEventListener("close", this._onModalClose)

      // Auto-open card if ?card=ID is in the URL
      const cardId = new URL(window.location.href).searchParams.get("card")
      if (cardId) this.#openCardById(cardId)
    }
  }

  disconnect() {
    if (this.hasCardDetailDialogTarget && this._onModalClose) {
      this.cardDetailDialogTarget.removeEventListener("close", this._onModalClose)
    }
  }

  openCard(event) {
    const cardId = event.currentTarget.dataset.cardId
    this.#openCardById(cardId)
  }

  #openCardById(cardId) {
    const url = `/tools/${this.toolIdValue}/board/cards/${cardId}`

    fetch(url, {
      headers: {
        "Accept": "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => response.text())
      .then(html => {
        if (this.hasCardModalTarget) {
          this.cardModalTarget.innerHTML = html
        }
        if (this.hasCardDetailDialogTarget) this.cardDetailDialogTarget.showModal()
      })
      .catch(error => {
        console.error("Error loading card:", error)
      })
  }

  // ── Column collapse ──

  collapseColumn(event) {
    event.stopPropagation()
    this.#toggleColumnCollapse(event.currentTarget.dataset.columnId, true)
  }

  expandColumn(event) {
    this.#toggleColumnCollapse(event.currentTarget.dataset.columnId, false)
  }

  #toggleColumnCollapse(columnId, collapsed) {
    const column = document.getElementById(`board-column-${columnId}`)
    column.classList.toggle("collapsed", collapsed)
    api(`/tools/${this.toolIdValue}/board/columns/${columnId}`, "PATCH", { collapsed })
  }

  // ── Column rename ──

  startRenameColumn(event) {
    const span = event.currentTarget
    const columnId = span.dataset.columnId
    const currentName = span.textContent.trim()

    const input = document.createElement("input")
    input.type = "text"
    input.value = currentName
    input.className = "board-column-name-input"

    const finishRename = async () => {
      const newName = input.value.trim()
      if (newName && newName !== currentName) {
        await api(`/tools/${this.toolIdValue}/board/columns/${columnId}`, "PATCH", { name: newName })
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

  // ── Archived cards toggle ──

  toggleArchived(event) {
    const columnId = event.currentTarget.dataset.columnId
    const section = this.archivedSectionTargets.find(s => s.dataset.columnId === columnId)
    const label = this.archivedToggleLabelTargets.find(l => l.dataset.columnId === columnId)
    if (section) {
      const isHidden = !section.classList.contains("flex")
      section.classList.toggle("hidden", !isHidden)
      section.classList.toggle("flex", isHidden)
      if (label) {
        const count = label.textContent.match(/\d+/)?.[0] || ""
        label.textContent = isHidden ? `Hide ${count} archived` : `${count} archived`
      }
    }
  }

  // ── Add card form ──

  addCardToFirstColumn() {
    const firstBtn = this.addCardBtnTargets[0]
    if (firstBtn) firstBtn.click()
  }

  showAddCard(event) {
    const columnId = event.currentTarget.dataset.columnId
    const form = this.addCardFormTargets.find(f => f.dataset.columnId === columnId)
    const input = this.addCardInputTargets.find(i => i.dataset.columnId === columnId)
    if (form) {
      event.currentTarget.classList.add("hidden")
      form.classList.add("active")
      input?.focus()
    }
  }

  hideAddCard(event) {
    const columnId = event.currentTarget.dataset.columnId
    this._hideAddCardForm(columnId)
  }

  addCardKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
    }
    if (event.key === "Escape") {
      this._hideAddCardForm(event.currentTarget.dataset.columnId)
    }
  }

  // ── Private ──

  _hideAddCardForm(columnId) {
    const form = this.addCardFormTargets.find(f => f.dataset.columnId === columnId)
    const input = this.addCardInputTargets.find(i => i.dataset.columnId === columnId)
    if (form) {
      form.classList.remove("active")
      if (input) input.value = ""
      const btn = this.addCardBtnTargets.find(b => b.dataset.columnId === columnId)
      if (btn) btn.classList.remove("hidden")
    }
  }
}
