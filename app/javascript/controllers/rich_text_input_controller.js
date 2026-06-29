import { Controller } from "@hotwired/stimulus"
import { Mention } from "rhino-editor"
import { createMentionSuggestion } from "services/mention_suggestion"

// Wraps a <rhino-editor> with form helpers:
// enter-to-submit, typing event dispatch, toolbar configuration, mentions, and clearing after submit.
export default class extends Controller {
  static targets = ["editor"]
  static values = {
    submitOnEnter: { type: Boolean, default: false },
    buttons: { type: Array, default: [] },
    mentions: { type: Array, default: [] }
  }

  connect() {
    this.editorTarget.addEventListener("rhino-change", this._onInput)

    if (this.submitOnEnterValue) {
      this.editorTarget.addEventListener("keydown", this._onKeydown)
    }

    if (this.buttonsValue.length > 0) {
      this._configureToolbar()
    }

    if (this.mentionsValue.length > 0) {
      this._configureMentions()
    }

    // Start the deferred editor after options are set
    this.editorTarget.startEditor()
  }

  disconnect() {
    this.editorTarget.removeEventListener("rhino-change", this._onInput)
    this.editorTarget.removeEventListener("keydown", this._onKeydown)
  }

  clear() {
    const input = document.getElementById(this.editorTarget.getAttribute("input"))
    if (input) input.value = ""
    this.editorTarget.editor?.commands.clearContent()
  }

  // ── Private ──

  _onInput = () => {
    this.dispatch("input")
  }

  _onKeydown = (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      // Let the mention dropdown claim Enter to pick a candidate.
      if (this.mentionActive) return

      const toolbar = this.editorTarget.querySelector("[role='toolbar']")
      if (toolbar?.querySelector("[popover]:popover-open, dialog[open]")) return

      event.preventDefault()
      const editor = this.editorTarget.editor
      if (editor && !editor.isEmpty) {
        this.editorTarget.closest("form")?.requestSubmit()
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
