import { Controller } from "@hotwired/stimulus"
import { apiPatch } from "services/api"
import { applyTheme } from "services/theme"

// Past this many characters the palette also searches every tool you share
const SEARCH_FROM_LENGTH = 2
const SEARCH_AFTER_MS = 200

export default class extends Controller {
  static targets = ["input", "results", "item", "sectionHeader", "sectionDivider", "searchFrame"]

  open() {
    clearTimeout(this.searchTimer)
    this.inputTarget.value = ""
    this.filter()
    this.element.showModal()
    this.inputTarget.focus()
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      // Search results already match; the server chose them
      if (item.dataset.searchResult) return

      if (!query) {
        // Themes only show once you type towards them: "theme", "nord"
        item.classList.toggle("hidden", "whenTyped" in item.dataset)
      } else {
        const name = item.dataset.name
        const type = item.dataset.type
        const match = name.includes(query) || type.includes(query)
        item.classList.toggle("hidden", !match)
      }
    })

    this._toggleEmptySections()
    this.#selectFirst()
    this._search(query)
  }

  // Asks the server for everything else that matches, once typing pauses
  _search(query) {
    if (!this.hasSearchFrameTarget) return

    clearTimeout(this.searchTimer)
    if (query.length < SEARCH_FROM_LENGTH) {
      this.searchFrameTarget.removeAttribute("src")
      this.searchFrameTarget.replaceChildren()
      return
    }

    this.searchTimer = setTimeout(() => {
      this.searchFrameTarget.src = `/search?q=${encodeURIComponent(query)}`
    }, SEARCH_AFTER_MS)
  }

  // The results arrived; if nothing above them matched, the first one is selected
  searched() {
    if (!this.#selectedItem || this.#selectedItem.classList.contains("hidden")) this.#selectFirst()
  }

  // Hide a section's header (and, for actions, the divider after it) once
  // filtering leaves nothing visible under it — otherwise a filter that only
  // matches tools leaves a dangling "ACTIONS" label with nothing below it.
  _toggleEmptySections() {
    const visible = (item) => !item.classList.contains("hidden")
    const sectionOf = (item) => [ "action", "theme" ].includes(item.dataset.type) ? item.dataset.type : "tool"
    const shown = new Set(this.itemTargets.filter(item => !item.dataset.searchResult && visible(item)).map(sectionOf))

    this.sectionHeaderTargets.forEach(header => header.classList.toggle("hidden", !shown.has(header.dataset.section)))
    this.sectionDividerTargets.forEach(divider => divider.classList.toggle("hidden", !shown.has("action")))
  }

  navigate(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.#moveSelection(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.#moveSelection(-1)
        break
      case "Enter":
        event.preventDefault()
        this.#activateSelected({ beside: event.altKey })
        break
    }
  }

  triggerAction(event) {
    const hotkey = event.currentTarget.dataset.hotkeyTrigger
    this.element.close()
    const target = this._findHotkeyElement(hotkey)
    if (!target) return

    // Some hotkey targets are the field itself (e.g. mail search), not a
    // button to click — clicking a text input doesn't focus it the way a
    // real mouse click would, since that focus comes from mousedown, which
    // .click() doesn't dispatch.
    if (target.matches("input, textarea, [contenteditable]")) {
      target.focus()
    } else {
      target.click()
    }
  }

  // Puts a theme on, here and on every other page this person has open
  async pickTheme(event) {
    this.element.close()
    const theme = await apiPatch("/appearance", { theme: event.currentTarget.dataset.theme || null })
    if (theme) applyTheme(theme)
  }

  // data-hotkey can list several hotkeys, separated by commas: "#,Shift+#".
  // A comma right after a + is the comma key: "Mod+,".
  _findHotkeyElement(hotkey) {
    return Array.from(document.querySelectorAll("[data-hotkey]"))
      .find(element => element.dataset.hotkey.split(/(?<!\+),/).includes(hotkey))
  }

  // Private

  get #visibleItems() {
    return this.itemTargets.filter(item => !item.classList.contains("hidden"))
  }

  get #selectedItem() {
    return this.itemTargets.find(item => item.classList.contains("selected"))
  }

  #selectFirst() {
    const visible = this.#visibleItems
    this.itemTargets.forEach(item => item.classList.remove("selected"))
    if (visible[0]) visible[0].classList.add("selected")
  }

  #moveSelection(direction) {
    const visible = this.#visibleItems
    if (!visible.length) return

    const current = this.#selectedItem
    const currentIndex = current ? visible.indexOf(current) : -1
    const nextIndex = Math.max(0, Math.min(visible.length - 1, currentIndex + direction))

    this.itemTargets.forEach(item => item.classList.remove("selected"))
    visible[nextIndex].classList.add("selected")
    visible[nextIndex].scrollIntoView({ block: "nearest" })
  }

  #activateSelected({ beside = false } = {}) {
    // Results can arrive a moment before the palette marks the first one, and
    // Enter pressed in that moment means that first one
    const selected = this.#selectedItem || this.#visibleItems[0]
    if (!selected) return

    // Actions click the element their hotkey is on; a theme puts itself on
    if (selected.dataset.hotkeyTrigger || selected.dataset.type === "theme") {
      selected.click()
      return
    }

    // Tool items have an href — navigate via Turbo, or with Alt open it beside
    // (side_pane_controller.js, which a page that is itself beside doesn't have)
    this.element.close()
    if (!selected.href) return

    if (beside && document.getElementById("side-pane")) {
      window.dispatchEvent(new CustomEvent("side-pane:open", { detail: { url: selected.href } }))
    } else {
      Turbo.visit(selected.href)
    }
  }
}
