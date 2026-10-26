import { Controller } from "@hotwired/stimulus"
import { visitPage } from "services/tile"

// Handles file uploads via form and drag-drop
export default class extends Controller {
  static targets = ["dropzone", "form", "input", "folderId", "button", "label"]

  // The page refreshes with a morph after the upload, which keeps this input and the
  // file picked in it: picking the same file again would change nothing, and nothing
  // would happen. The form has taken the files by the time requestSubmit returns.
  upload(event) {
    if (event.target.files.length > 0) {
      this.#uploading(event.target.files.length)
      this.formTarget.requestSubmit()
      event.target.value = ""
    }
  }

  // Drag and drop for external files
  dragOver(event) {
    if (!this.#isExternalDrag(event)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
  }

  dragEnter(event) {
    if (!this.#isExternalDrag(event)) return
    event.preventDefault()
    this.dropzoneTarget.classList.add("drag-active")
  }

  dragLeave(event) {
    if (!this.dropzoneTarget.contains(event.relatedTarget)) {
      this.dropzoneTarget.classList.remove("drag-active")
    }
  }

  async drop(event) {
    if (!this.#isExternalDrag(event)) return
    event.preventDefault()
    this.dropzoneTarget.classList.remove("drag-active")

    const files = event.dataTransfer.files
    if (files.length === 0) return

    await this.#uploadFiles(files)
  }

  // Private

  #isExternalDrag(event) {
    return event.dataTransfer.types.includes("Files") &&
           !event.dataTransfer.types.includes("application/json")
  }

  async #uploadFiles(files) {
    const formData = new FormData()
    const folderId = this.hasFolderIdTarget ? this.folderIdTarget.value : ""

    if (folderId) formData.append("folder_id", folderId)
    this.#uploading(files.length)
    for (const file of files) formData.append("files[]", file)

    try {
      // (through Turbo: the page knows the change for its own, live_controller.js)
      const response = await Turbo.fetch(this.formTarget.action, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": this.#csrfToken,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        visitPage(this.element)
      } else {
        this.#uploaded()
        const data = await response.json()
        alert(data.errors?.join(", ") || "Upload failed")
      }
    } catch (error) {
      this.#uploaded()
      console.error("Upload error:", error)
      alert("Upload failed")
    }
  }

  // On a phone's network an upload takes a while: the button says it is under way
  // until the page is drawn again with the files in it (which puts the button back)
  #uploading(count) {
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = count > 1 ? `Uploading ${count} files…` : "Uploading…"
    this.buttonTarget.setAttribute("aria-busy", "true")
  }

  #uploaded() {
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = "Upload"
    this.buttonTarget.removeAttribute("aria-busy")
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
