import { Controller } from "@hotwired/stimulus"

// The dialog a file is shown in (shared/file_viewer). A link anywhere on the page that
// names its frame loads the file's page into it; the dialog opens as that starts, so
// there is something to see while a large spreadsheet is read. Closed, it holds nothing:
// a video stops, and the same file can be asked for again.
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.opening = this.opening.bind(this)
    this.emptied = this.emptied.bind(this)
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.opening)
    this.element.addEventListener("close", this.emptied)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.opening)
    this.element.removeEventListener("close", this.emptied)
  }

  opening() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    this.element.close()
  }

  emptied() {
    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren()
  }
}
