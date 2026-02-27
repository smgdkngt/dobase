import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "item"]

  open() {
    this.inputTarget.value = ""
    this.filter()
    this.element.showModal()
    this.inputTarget.focus()
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      if (!query) {
        item.classList.remove("hidden")
      } else {
        const name = item.dataset.name
        const type = item.dataset.type
        const match = name.includes(query) || type.includes(query)
        item.classList.toggle("hidden", !match)
      }
    })

    this.#selectFirst()
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
    const target = document.querySelector(`[data-hotkey="${hotkey}"]`)
    if (target) target.click()
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
    const selected = this.#selectedItem
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
