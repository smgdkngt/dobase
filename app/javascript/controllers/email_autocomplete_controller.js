import { Controller } from "@hotwired/stimulus"

// Autocomplete for email recipient fields (To, Cc, Bcc).
// Supports multiple comma-separated addresses with contact suggestions.
export default class extends Controller {
  static targets = ["input", "hidden", "tags", "results"]
  static values = { url: String }

  connect() {
    this._addresses = []
    this._selectedIndex = -1

    // Parse any pre-filled addresses
    const initial = this.hiddenTarget.value
    if (initial) {
      initial.split(/,\s*/).filter(Boolean).forEach(addr => this._addAddress(addr, false))
    }

    this.inputTarget.addEventListener("input", this._onInput)
    this.inputTarget.addEventListener("keydown", this._onKeydown)
    this.inputTarget.addEventListener("blur", this._onBlur)
    document.addEventListener("click", this._onClickOutside)
  }

  disconnect() {
    this.inputTarget.removeEventListener("input", this._onInput)
    this.inputTarget.removeEventListener("keydown", this._onKeydown)
    this.inputTarget.removeEventListener("blur", this._onBlur)
    document.removeEventListener("click", this._onClickOutside)
  }

  // --- Events ---

  _onInput = () => {
    clearTimeout(this._debounce)
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this._hideResults()
      return
    }
    this._debounce = setTimeout(() => this._search(query), 200)
  }

  _onKeydown = (event) => {
    const results = this._visibleResults()

    switch (event.key) {
      case "Enter":
      case "Tab":
      case ",":
        if (this._selectedIndex >= 0 && results.length > 0) {
          event.preventDefault()
          results[this._selectedIndex]?.click()
        } else if (this.inputTarget.value.trim()) {
          event.preventDefault()
          this._commitInput()
        }
        break
      case "Backspace":
        if (!this.inputTarget.value && this._addresses.length > 0) {
          this._removeAddress(this._addresses.length - 1)
        }
        break
      case "ArrowDown":
        if (results.length > 0) {
          event.preventDefault()
          this._selectedIndex = Math.min(this._selectedIndex + 1, results.length - 1)
          this._highlightResult()
        }
        break
      case "ArrowUp":
        if (results.length > 0) {
          event.preventDefault()
          this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
          this._highlightResult()
        }
        break
      case "Escape":
        this._hideResults()
        break
    }
  }

  _onBlur = () => {
    // Delay to allow click on result
    setTimeout(() => {
      if (this.inputTarget.value.trim()) this._commitInput()
      this._hideResults()
    }, 200)
  }

  _onClickOutside = (event) => {
    if (!this.element.contains(event.target)) {
      this._hideResults()
    }
  }

  // --- Actions ---

  removeTag(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this._removeAddress(index)
    this.inputTarget.focus()
  }

  selectResult(event) {
    const email = event.currentTarget.dataset.email
    const name = event.currentTarget.dataset.name
    if (email) {
      this._addAddress(name ? `${name} <${email}>` : email)
      this.inputTarget.value = ""
      this._hideResults()
      this.inputTarget.focus()
    }
  }

  // --- Internal ---

  _commitInput() {
    const value = this.inputTarget.value.replace(/,\s*$/, "").trim()
    if (value) {
      this._addAddress(value)
      this.inputTarget.value = ""
    }
  }

  _addAddress(address, sync = true) {
    this._addresses.push(address)
    this._renderTag(address, this._addresses.length - 1)
    if (sync) this._syncHidden()
  }

  _removeAddress(index) {
    this._addresses.splice(index, 1)
    this._renderAllTags()
    this._syncHidden()
  }

  _syncHidden() {
    this.hiddenTarget.value = this._addresses.join(", ")
  }

  _renderTag(address, index) {
    const tag = document.createElement("span")
    tag.className = "inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-background-secondary text-sm text-text-primary"
    tag.innerHTML = `
      <span class="truncate max-w-48">${this._escapeHtml(this._displayAddress(address))}</span>
      <button type="button" class="text-text-tertiary hover:text-text-primary ml-0.5" data-index="${index}" data-action="click->email-autocomplete#removeTag">&times;</button>
    `
    this.tagsTarget.appendChild(tag)
  }

  _renderAllTags() {
    this.tagsTarget.innerHTML = ""
    this._addresses.forEach((addr, i) => this._renderTag(addr, i))
  }

  _displayAddress(address) {
    const match = address.match(/^(.+?)\s*<(.+?)>$/)
    return match ? match[1] : address
  }

  async _search(query) {
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(query)}`
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return

      const contacts = await response.json()
      this._showResults(contacts)
    } catch {
      // silently fail
    }
  }

  _showResults(contacts) {
    this._selectedIndex = -1
    if (contacts.length === 0) {
      this._hideResults()
      return
    }

    // Filter out already-added addresses
    const existing = new Set(this._addresses.map(a => {
      const match = a.match(/<(.+?)>/)
      return (match ? match[1] : a).toLowerCase()
    }))

    const filtered = contacts.filter(c => !existing.has(c.email_address.toLowerCase()))
    if (filtered.length === 0) {
      this._hideResults()
      return
    }

    this.resultsTarget.innerHTML = filtered.map(contact => `
      <button type="button"
              class="flex items-center gap-2 w-full px-3 py-2 text-left text-sm hover:bg-background-secondary transition-colors"
              data-action="click->email-autocomplete#selectResult"
              data-email="${this._escapeAttr(contact.email_address)}"
              data-name="${this._escapeAttr(contact.name || "")}">
        <span class="font-medium text-text-primary truncate">${this._escapeHtml(contact.name || contact.email_address)}</span>
        ${contact.name ? `<span class="text-text-tertiary truncate">&lt;${this._escapeHtml(contact.email_address)}&gt;</span>` : ""}
      </button>
    `).join("")

    this.resultsTarget.classList.remove("hidden")
  }

  _hideResults() {
    this.resultsTarget.classList.add("hidden")
    this._selectedIndex = -1
  }

  _visibleResults() {
    if (this.resultsTarget.classList.contains("hidden")) return []
    return [...this.resultsTarget.querySelectorAll("button")]
  }

  _highlightResult() {
    this._visibleResults().forEach((el, i) => {
      el.classList.toggle("bg-background-secondary", i === this._selectedIndex)
    })
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  _escapeAttr(str) {
    return str.replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
