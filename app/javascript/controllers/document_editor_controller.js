import { Controller } from "@hotwired/stimulus"
import { Collaboration, CollaborationCaret, Mention } from "rhino-editor"
import { applyPlaceholder } from "services/rhino_placeholder"
import { DocumentSync } from "services/document_sync"
import { createMentionSuggestion } from "services/mention_suggestion"
import { api } from "services/api"
import { reloadPage, tileOf } from "services/tile"

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
    this.loaded = false
    this.startingOver = false

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
    clearTimeout(this.waiting)
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
      onSynced: ({ seed, compact }) => this.onSynced(seed, compact),
      // The others don't have that change, so saying "Saved" would be wrong
      onRefused: (reason) => this.showSaveIndicator(reason, true),
      onReplaced: () => this.startOver()
    })
    this.sync.describeMe({ name: this.userNameValue, color: this.userColorValue })
    this.sync.awareness.on("change", (changes, origin) => this._showNamesOfMoved(changes, origin))

    this.editorTarget.addExtensions(
      Collaboration.configure({ document: this.sync.doc }),
      CollaborationCaret.configure({
        provider: this.sync,
        user: { name: this.userNameValue, color: this.userColorValue },
        render: (user) => this._caretFor(user)
      }),
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

    // Until the shared copy is here the editor is empty and the document isn't:
    // nothing can be typed in it yet, and after a few seconds of that it says why
    this.editorTarget.inert = true
    this.waiting = setTimeout(() => this.showSaveIndicator("Connecting..."), 3000)
  }

  // Someone else's caret: a line in their colour with their name on it, the
  // markup the caret styles expect. The name shows for a moment where the caret
  // lands, then fades (see docs.css).
  _caretFor(user) {
    const caret = document.createElement("span")
    caret.classList.add("collaboration-carets__caret")
    caret.style.borderColor = user.color

    const label = document.createElement("div")
    label.classList.add("collaboration-carets__label")
    label.style.backgroundColor = user.color
    label.dataset.caretName = user.name
    label.textContent = user.name
    caret.appendChild(label)
    return caret
  }

  // The editor keeps a moved caret's element, so its name wouldn't show again
  // by itself: play it again for everyone whose caret just changed
  _showNamesOfMoved({ added, updated }, origin) {
    if (origin !== this.sync) return

    const states = this.sync.awareness.getStates()
    const names = added.concat(updated).map((id) => states.get(id)?.user?.name).filter(Boolean)
    if (names.length === 0) return

    requestAnimationFrame(() => {
      this.editorTarget.querySelectorAll("[data-caret-name]").forEach((label) => {
        if (!names.includes(label.dataset.caretName)) return
        label.getAnimations().forEach((animation) => {
          animation.cancel()
          animation.play()
        })
      })
    })
  }

  // The first page to open a document since this was built fills the shared copy
  // with the text as it was saved; everyone after joins what that page made.
  async onSynced(seed, compact) {
    // The copy can be here before the editor is: a tab opened in the background
    // takes its time starting one, and the text would be handed to nobody
    await this.editorTarget.initializationComplete
    if (!this.sync || this.startingOver) return

    if (seed !== null && seed !== undefined) {
      const html = seed || this.savedHtml
      if (html) this.editorTarget.editor?.commands.setContent(html)
    }
    // Only now is what the editor holds the document: it can be written in, and saved
    this.loaded = true
    this.editorTarget.inert = false
    clearTimeout(this.waiting)
    if (this.hasSaveIndicatorTarget && this.saveIndicatorTarget.textContent === "Connecting...") this.showSaveIndicator("Saved")

    if (compact) this.sync.compact()
  }

  // The shared copy this page writes in was thrown away, most often because
  // the text was replaced from outside the editor (the API). This page still
  // shows the old text, so it opens the document again — without saving on the
  // way out, which would put the old text back.
  startOver() {
    if (this.startingOver) return

    this.startingOver = true
    this.sync?.abandon()
    clearTimeout(this.saveTimeout)
    this.saveTimeout = null
    reloadPage(this.element)
  }

  setupKeyboardShortcuts() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  removeKeyboardShortcuts() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // (in a tile that is part of the workspace's page, only while the keyboard is in it)
    if (tileOf(this.element) && !this.element.contains(document.activeElement)) return

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
    if (this.startingOver) return

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
      // Until the shared copy has arrived the editor is empty and the document
      // isn't. A new title can be saved by then; the text stays as it is.
      if (!this.loaded) formData.delete("docs_document[content]")

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
