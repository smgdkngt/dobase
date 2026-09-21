import { Controller } from "@hotwired/stimulus"

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
        item.classList.remove("hidden")
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
    const hasVisibleAction = this.itemTargets.some(item => item.dataset.type === "action" && visible(item))
    const hasVisibleTool = this.itemTargets.some(item => item.dataset.type !== "action" && !item.dataset.searchResult && visible(item))

    this.sectionHeaderTargets.forEach(header => {
      header.classList.toggle("hidden", !(header.dataset.section === "action" ? hasVisibleAction : hasVisibleTool))
    })
    this.sectionDividerTargets.forEach(divider => divider.classList.toggle("hidden", !hasVisibleAction))
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
        this.#activateSelected()
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

  #activateSelected() {
    // Results can arrive a moment before the palette marks the first one, and
    // Enter pressed in that moment means that first one
    const selected = this.#selectedItem || this.#visibleItems[0]
    if (!selected) return

    // Action items have a hotkey trigger — click the hotkey element
    if (selected.dataset.hotkeyTrigger) {
      selected.click()
      return
    }

    // Tool items have an href — navigate via Turbo
    this.element.close()
    if (selected.href) Turbo.visit(selected.href)
  }
}
