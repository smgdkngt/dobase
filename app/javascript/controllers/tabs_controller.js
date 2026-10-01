import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { default: String }

  connect() {
    // Check turbo frame src URL first, then page URL
    const frame = this.element.closest("turbo-frame")
    const frameSrc = frame?.getAttribute("src")
    const tabFromFrame = frameSrc ? new URL(frameSrc, window.location.origin).searchParams.get("tab") : null
    const tabFromUrl = new URL(window.location.href).searchParams.get("tab")
    const defaultTab = tabFromFrame || tabFromUrl || this.defaultValue || this.tabTargets[0]?.dataset.tab
    if (defaultTab) this.show(defaultTab)

    // A morph refresh (a form here redirecting back to this page) puts the server's
    // HTML back, in which no tab is open yet, without connecting this again
    this.showAgain = () => { if (this.current) this.show(this.current) }
    document.addEventListener("turbo:morph", this.showAgain)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.showAgain)
  }

  select(event) {
    event.preventDefault()
    this.show(event.currentTarget.dataset.tab)
  }

  show(tabName) {
    this.current = tabName
    this.tabTargets.forEach(tab => {
      tab.classList.toggle("active", tab.dataset.tab === tabName)
    })
    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tabName)
    })
  }
}
