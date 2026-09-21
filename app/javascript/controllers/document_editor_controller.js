import { Controller } from "@hotwired/stimulus"
import { Collaboration, CollaborationCaret, Mention } from "rhino-editor"
import { applyPlaceholder } from "services/rhino_placeholder"
import { DocumentSync } from "services/document_sync"
import { createMentionSuggestion } from "services/mention_suggestion"
import { api } from "services/api"

export default class extends Controller {
  static targets = ["form", "title", "editor", "saveIndicator"]
  static values = {
    documentId: Number,
    saveUrl: String,
    userName: String,
    userColor: String,
    mentions: Array,
    mentionUrl: String
  }

  connect() {
    this.saveTimeout = null
    this.isSaving = false
    this.pendingSave = false
    this.lastSavedTitle = this.titleTarget.value

    // The editor is deferred so its options can be set before it starts
    applyPlaceholder(this.editorTarget)
    this.startSharedEditing()
    this.setupKeyboardShortcuts()
    this.saveBeforeLeaving = () => this.flushPendingSave({ keepalive: true })
    window.addEventListener("pagehide", this.saveBeforeLeaving)
  }

  disconnect() {
    // Leaving the page (a Turbo visit keeps the document alive, so the save still goes through)
    this.flushPendingSave()
    window.removeEventListener("pagehide", this.saveBeforeLeaving)
    this.sync?.destroy()
    this.sync = null
    this.removeKeyboardShortcuts()
  }

  // Everyone in the document writes in the same Yjs copy, which merges what
  // people type at the same time. The editor starts empty and fills from that
  // copy: handing it the saved HTML as well would add a second copy of the text
  // on every visit.
  startSharedEditing() {
    this.sync = new DocumentSync(this.documentIdValue, {
      onSynced: ({ seed, compact }) => this.onSynced(seed, compact)
    })
    this.sync.describeMe({ name: this.userNameValue, color: this.userColorValue })

    this.editorTarget.addExtensions(
      Collaboration.configure({ document: this.sync.doc }),
      CollaborationCaret.configure({ provider: this.sync, user: { name: this.userNameValue, color: this.userColorValue } }),
      Mention.configure({
        HTMLAttributes: { class: "mention" },
        suggestion: createMentionSuggestion({
          users: this.mentionsValue,
          // Only the page where the name was picked tells the colleague
          onPick: (user) => api(this.mentionUrlValue, "POST", { user_id: user.id })
        })
      })
    )

    // The shared copy keeps the history — one editor undoing its own steps on
    // top of that would undo other people's words too
    this.editorTarget.starterKitOptions = { ...(this.editorTarget.starterKitOptions || {}), undoRedo: false }

    const input = document.getElementById(this.editorTarget.getAttribute("input"))
    this.savedHtml = input?.value || ""
    if (input) input.value = ""
    this.editorTarget.startEditor()
  }

  // The first page to open a document since this was built fills the shared copy
  // with the text as it was saved; everyone after joins what that page made.
  onSynced(seed, compact) {
    if (seed !== null && seed !== undefined) {
      const html = seed || this.savedHtml
      if (html) this.editorTarget.editor?.commands.setContent(html)
    }

    if (compact) this.sync.compact()
  }

  setupKeyboardShortcuts() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  removeKeyboardShortcuts() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "s") {
      event.preventDefault()
      if (this.saveTimeout) clearTimeout(this.saveTimeout)
      this.save()
    }
  }

  // Saves right away what the autosave was still waiting to save
  flushPendingSave({ keepalive = false } = {}) {
    if (!this.saveTimeout) return

    clearTimeout(this.saveTimeout)
    this.saveTimeout = null
    this.save({ keepalive })
  }

  scheduleAutoSave() {
    if (this.saveTimeout) clearTimeout(this.saveTimeout)
    this.showSaveIndicator("Editing...")
    this.saveTimeout = setTimeout(() => this.save(), 2000)
  }

  // keepalive lets the request outlive a closing tab (for bodies up to 64 KB)
  async save({ keepalive = false } = {}) {
    this.saveTimeout = null
    if (this.isSaving) {
      this.pendingSave = true
      return
    }

    this.isSaving = true
    this.pendingSave = false
    this.showSaveIndicator("Saving...")

    try {
      const formData = new FormData(this.formTarget)
      formData.set("docs_document[title]", this.titleTarget.value)

      const response = await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json"
        },
        body: formData,
        keepalive
      })

      if (response.ok) {
        this.lastSavedTitle = this.titleTarget.value
        this.showSaveIndicator("Saved")
      } else {
        this.showSaveIndicator("Save failed", true)
      }
    } catch {
      this.showSaveIndicator("Save failed", true)
    } finally {
      this.isSaving = false

      if (this.pendingSave) {
        setTimeout(() => this.save(), 100)
      }
    }
  }

  showSaveIndicator(status, isError = false) {
    if (!this.hasSaveIndicatorTarget) return

    const indicator = this.saveIndicatorTarget
    indicator.classList.remove("text-error", "text-success")

    if (isError) {
      indicator.classList.add("text-error")
    } else if (status === "Saved") {
      indicator.classList.add("text-success")
    }

    indicator.textContent = status
  }
}
