import { Controller } from "@hotwired/stimulus"
import { Mention } from "rhino-editor"
import { createMentionSuggestion } from "services/mention_suggestion"
import { applyPlaceholder } from "services/rhino_placeholder"
import { readDraft, keepDraft, dropDraft } from "services/drafts"

// Wraps a <rhino-editor> with form helpers:
// enter-to-submit, typing event dispatch, toolbar configuration, mentions, and clearing after submit.
// With a draft name it keeps what is typed in this tab until it is sent or cancelled, and
// puts it back when the field is drawn again (a card's dialog closed and opened), saying
// "rich-text-input:restored" so a view can show the field it is in.
export default class extends Controller {
  static targets = ["editor"]
  static values = {
    submitOnEnter: { type: Boolean, default: false },
    buttons: { type: Array, default: [] },
    mentions: { type: Array, default: [] },
    draft: String
  }

  connect() {
    this.editorTarget.addEventListener("rhino-change", this._onInput)

    if (this.submitOnEnterValue) {
      this.editorTarget.addEventListener("keydown", this._noteMentionKey, true)
      this.editorTarget.addEventListener("keydown", this._onKeydown)
    }

    if (this.buttonsValue.length > 0) {
      this._configureToolbar()
    }

    if (this.mentionsValue.length > 0) {
      this._configureMentions()
    }

    applyPlaceholder(this.editorTarget)

    if (this.draftValue) {
      this.editorTarget.addEventListener("rhino-initialize", this._restoreDraft)
      this._form = this.element.closest("form")
      this._form?.addEventListener("turbo:submit-start", this._sending)
      this._form?.addEventListener("turbo:submit-end", this._sent)
    }

    // Start the deferred editor after options are set
    this.editorTarget.startEditor()
  }

  disconnect() {
    this.editorTarget.removeEventListener("rhino-change", this._onInput)
    this.editorTarget.removeEventListener("keydown", this._noteMentionKey, true)
    this.editorTarget.removeEventListener("keydown", this._onKeydown)
    this.editorTarget.removeEventListener("rhino-initialize", this._restoreDraft)
    this._form?.removeEventListener("turbo:submit-start", this._sending)
    this._form?.removeEventListener("turbo:submit-end", this._sent)
  }

  // Cancelled: what was typed is let go of, and the field shows what it had
  discardDraft() {
    if (!this.draftValue) return

    dropDraft(this.draftValue)
    const editor = this.editorTarget.editor
    if (editor && this._initial !== undefined) {
      editor.commands.setContent(this._initial)
      this.editorTarget.updateInputElementValue()
    }
  }

  clear() {
    const input = document.getElementById(this.editorTarget.getAttribute("input"))
    if (input) input.value = ""
    this.editorTarget.editor?.commands.clearContent()
  }

  // ── Private ──

  _onInput = () => {
    this.dispatch("input")
    this._keepDraft()
  }

  // The editor is up with what the server drew: that is what a draft differs from
  _restoreDraft = () => {
    this._initial = this.editorTarget.serialize()
    this._initiallyEmpty = !!this.editorTarget.editor?.isEmpty
    const draft = readDraft(this.draftValue, this._initial)
    if (draft === null || draft === this._initial) return

    this.editorTarget.editor?.commands.setContent(draft)
    this.editorTarget.updateInputElementValue()
    this.dispatch("restored")
  }

  _keepDraft() {
    if (!this.draftValue || this._initial === undefined || this._sendingText !== undefined) return

    const editor = this.editorTarget.editor
    if (!editor) return
    if (editor.isEmpty && this._initiallyEmpty) dropDraft(this.draftValue)
    else keepDraft(this.draftValue, editor.isEmpty ? "" : this.editorTarget.serialize(), this._initial)
  }

  // Let go of as it goes, so the field drawn with the answer starts empty; kept again
  // when it didn't go through
  _sending = () => {
    this._sendingText = this.editorTarget.serialize()
    dropDraft(this.draftValue)
  }

  _sent = (event) => {
    const text = this._sendingText
    this._sendingText = undefined
    if (!event.detail.success && text !== undefined) keepDraft(this.draftValue, text, this._initial ?? "")
  }

  // The editor hears a key before this controller does (it is inside it), and an Enter
  // that picks someone from the mention list closes the list on the way. So whether the
  // list was open is noted on the way in, before the editor has the key.
  _noteMentionKey = (event) => {
    if (this.mentionActive) this._mentionKey = event
  }

  _onKeydown = (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      // Let the mention dropdown claim Enter to pick a candidate. (Not by defaultPrevented:
      // the editor prevents the default of every Enter it handles, a new line too.)
      if (this.mentionActive || event === this._mentionKey) return

      const toolbar = this.editorTarget.querySelector("[role='toolbar']")
      if (toolbar?.querySelector("[popover]:popover-open, dialog[open]")) return

      event.preventDefault()
      const editor = this.editorTarget.editor
      const form = this.editorTarget.closest("form")
      // Turbo marks a form busy while it is being sent. The text stays in the editor until
      // the answer is in, so on a slow connection a second Enter sent it a second time.
      if (form?.getAttribute("aria-busy") === "true") return

      if (editor && !editor.isEmpty) {
        form?.requestSubmit()
      }
    }
  }

  _configureMentions() {
    const users = this.mentionsValue
    this.editorTarget.addExtensions(
      Mention.configure({
        HTMLAttributes: { class: "mention" },
        suggestion: createMentionSuggestion({
          users,
          onStateChange: (active) => { this.mentionActive = active }
        })
      })
    )
  }

  _configureToolbar() {
    const keep = new Set(this.buttonsValue)

    const allFeatures = [
      "bold", "italic", "strike", "link", "heading", "blockquote",
      "codeBlock", "bulletList", "orderedList", "attachmentGallery",
      "decreaseIndentation", "increaseIndentation", "undo", "redo"
    ]

    const nameMap = { code: "codeBlock" }

    const starterKitOptions = {
      rhinoSelection: false,
      rhinoAttachment: false,
      rhinoGallery: false
    }
    for (const feature of allFeatures) {
      const keepName = Object.entries(nameMap).find(([, v]) => v === feature)?.[0] || feature
      if (!keep.has(keepName) && !keep.has(feature)) {
        starterKitOptions[feature] = false
      }
    }

    this.editorTarget.starterKitOptions = starterKitOptions
  }
}
