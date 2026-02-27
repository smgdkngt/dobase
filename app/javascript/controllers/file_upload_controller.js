import { Controller } from "@hotwired/stimulus"

// Handles file uploads via form and drag-drop
export default class extends Controller {
  static targets = ["dropzone", "form", "input", "folderId"]

  upload(event) {
    if (event.target.files.length > 0) {
      this.formTarget.requestSubmit()
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
    for (const file of files) formData.append("files[]", file)

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": this.#csrfToken,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        Turbo.visit(window.location.href, { action: "replace" })
      } else {
        const data = await response.json()
        alert(data.errors?.join(", ") || "Upload failed")
      }
    } catch (error) {
      console.error("Upload error:", error)
      alert("Upload failed")
    }
  }

  get #csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
