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
    this.drawing = this.drawing.bind(this)
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.opening)
    this.frameTarget.addEventListener("turbo:before-frame-render", this.drawing)
    this.element.addEventListener("close", this.emptied)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.opening)
    this.frameTarget.removeEventListener("turbo:before-frame-render", this.drawing)
    this.element.removeEventListener("close", this.emptied)
  }

  // A dialog says "close" a moment after it closed. A file asked for within that moment
  // has the dialog open again by then, so what was left of the last one goes here.
  opening() {
    if (this.element.open) return

    this.frameTarget.replaceChildren()
    this.element.showModal()
  }

  // A file that has arrived is drawn a moment later, and stopping what is loading doesn't
  // stop that. So it is asked as the file is drawn whether the dialog is still open:
  // closed, it stays empty.
  drawing(event) {
    const draw = event.detail.render

    event.detail.render = (frame, arrived) => {
      if (this.element.open) draw(frame, arrived)
    }
  }

  close() {
    this.element.close()
  }

  // Not when the dialog is open again: taking the address away stops what is loading,
  // and the dialog would wait for a file that never comes.
  emptied() {
    if (this.element.open) return

    this.frameTarget.removeAttribute("src")
    this.frameTarget.replaceChildren()
  }
}
