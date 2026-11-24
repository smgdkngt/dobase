import { Controller } from "@hotwired/stimulus"
import { formatFileSize } from "services/file_size"
import { tileOf } from "services/tile"
import { csrfToken } from "services/api"
import { showFlash } from "services/flash"
import { AUTOSAVE_DELAY, RETRY_DELAY, SEND_WAIT, hasUnsaved, fitsKeepalive, savedAt, settlesWithin } from "services/draft_autosave"
import { _ } from "services/i18n"

const FILE_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"></path><polyline points="13 2 13 9 20 9"></polyline></svg>'

// What the server says too (SmtpSendService::NO_RECIPIENTS)
const NO_RECIPIENTS = "Add a recipient: To, Cc or Bcc is empty."

export default class extends Controller {
  static targets = ["to", "ccField", "bccField", "fileInput", "attachmentsList", "quote", "quotedMessage", "quoteFrame", "gone", "send",
    "draftId", "saveDraft", "discard", "saveStatus"]
  // draftsUrl and mailsUrl: where a draft is saved (Tools::Mails::DraftsController) and
  // deleted, a draft's id appended
  static values = { unsent: Boolean, draftUrl: String, draftsUrl: String, mailsUrl: String, autosaveDelay: { type: Number, default: AUTOSAVE_DELAY } }

  connect() {
    this.files = []
    this._submitting = false
    this._snapshot = null
    // What the draft holds of this form, as of its last save from here
    this._savedSnapshot = null
    this._saving = null
    this._saveTimer = null
    this._waitingToSubmit = false
    this._doneWaiting = false
    this._discarded = false

    // Leaving the page: what isn't saved yet goes now, in a request that outlives the
    // page, and the browser still asks, since it may not get there
    this._beforeUnload = (e) => {
      if (this._mustAsk()) {
        this._save()
        e.preventDefault()
        e.returnValue = ""
      }
    }
    // A tab put away, a phone locked: it may never come back (a tab closed from the
    // task switcher, a battery that runs out), so the draft is saved now
    this._hidden = () => { if (document.visibilityState === "hidden") this._save() }
    this._pageHide = () => this._save()
    // In a tile that is part of the workspace's page, a visit of the window is not
    // this form's leaving: the tile is asked instead (tile:leaving, below)
    this._tile = tileOf(this.element)
    this._beforeVisit = (e) => {
      if (this._tile) return
      if (this._mustAsk()) {
        if (!confirm(_("You have an unsent message. Discard it?"))) {
          e.preventDefault()
        }
      }
    }
    // A conversation picked from the list opens in the pane this form is in, without a visit
    this._frameClick = (e) => {
      // (in such a tile every link in it goes somewhere in the tile, unless it says _top:
      // those the workspace asks about). A file opened in the viewer goes nowhere.
      const link = this._tile?.contains(e.target)
        ? e.target.closest?.("a[href]:not([data-turbo-frame='_top'], [data-turbo-frame='file_viewer'], [target='_blank'], [download])")
        : e.target.closest?.("a[data-turbo-frame]:not([data-turbo-frame='_top'], [data-turbo-frame='file_viewer'])")
      if (!link || this.element.contains(link)) return
      if (this._mustAsk() && !confirm(_("You have an unsent message. Discard it?"))) {
        e.preventDefault()
        e.stopImmediatePropagation()
      }
    }
    // What the workspace asks a tile before it closes it or sends it elsewhere. What isn't
    // saved yet is sent on its way, as a document being written sends its last words.
    this._tileLeaving = (e) => {
      if (!this._mustAsk()) return
      this._save()
      e.preventDefault()
    }
    this._tile?.addEventListener("tile:leaving", this._tileLeaving)
    window.addEventListener("beforeunload", this._beforeUnload)
    window.addEventListener("pagehide", this._pageHide)
    document.addEventListener("visibilitychange", this._hidden)
    document.addEventListener("turbo:before-visit", this._beforeVisit)
    document.addEventListener("click", this._frameClick, true)

    this.element.addEventListener("submit", (event) => {
      // Send with nobody to send it to says so, and stays (Save Draft goes elsewhere and
      // may: a draft can wait for its recipients). The server refuses it too.
      if (this._sendsToNobody(event.submitter)) {
        event.preventDefault()
        showFlash(_(NO_RECIPIENTS), "alert")
        if (this.hasToTarget) this.toTarget.focus()
        return
      }
      // Sent (or saved) while a save is on its way, it waits for that save: the first one
      // makes the draft the form would otherwise make a second time, and any of them could
      // land after Send and be refused, or write over what Send took. It waits a few
      // seconds at most, so a save that hangs never holds the mail back.
      if (!this._doneWaiting && (this._saving || this._waitingToSubmit)) {
        event.preventDefault()
        if (this._waitingToSubmit) return

        this._waitingToSubmit = true
        const submitter = event.submitter
        settlesWithin(this._saving, SEND_WAIT).then((settled) => {
          this._waitingToSubmit = false
          // Still on its way, the save is left behind. A first save makes a draft of its
          // own when it lands, which is deleted then (_send); a later one finds its draft
          // sent and changes nothing (Tools::Mails::DraftsController#update).
          if (!settled && !this._draftId()) this._discarded = true
          // A draft found sent or deleted elsewhere meanwhile has its buttons switched off
          if (submitter && (!submitter.isConnected || submitter.disabled)) return

          this._doneWaiting = true
          try {
            this.element.requestSubmit(submitter)
          } finally {
            this._doneWaiting = false
          }
        })
        return
      }
      this._submitting = true
      clearTimeout(this._saveTimer)
    })

    // The draft can be sent or deleted elsewhere (another window, the CLI) while it is
    // open here. The mailbox hears that something changed; then this form looks whether
    // its draft is still a draft, so it isn't sent a second time from here.
    this._presence = this.element.closest("[data-controller~='presence']")
    this._changed = () => this._checkDraft()
    this._presence?.addEventListener("presence:changed", this._changed)

    // Back from a failed send, the message is saved nowhere yet
    if (this.unsentValue) this.changed()
  }

  disconnect() {
    clearTimeout(this._saveTimer)
    this._presence?.removeEventListener("presence:changed", this._changed)
    this._tile?.removeEventListener("tile:leaving", this._tileLeaving)
    window.removeEventListener("beforeunload", this._beforeUnload)
    window.removeEventListener("pagehide", this._pageHide)
    document.removeEventListener("visibilitychange", this._hidden)
    document.removeEventListener("turbo:before-visit", this._beforeVisit)
    document.removeEventListener("click", this._frameClick, true)
  }

  // Changes count from when someone first reaches for the form, before their input lands.
  // What a reply, forward or draft starts with isn't an edit, and neither is the editor
  // putting that body in its own HTML once it has started.
  startEditing() {
    this._snapshot ??= this._formSnapshot()
  }

  // Something may have changed in the form (typed, a recipient added or dragged, a file
  // taken off, the quote changed in its frame): the draft is saved once that has rested
  // a few seconds. Whether there is anything to save is looked at then.
  changed() {
    if (this._submitting || this._isGone()) return
    clearTimeout(this._saveTimer)
    this._saveTimer = setTimeout(() => this._save(), this.autosaveDelayValue)
  }

  // Cmd+Enter (Ctrl+Enter elsewhere) sends, from wherever the keyboard is in the form. Heard
  // before the editor, which would make it a line break; @github/hotkey skips the editor.
  sendWithKeys(event) {
    if (event.key !== "Enter" || !(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey || event.isComposing) return
    event.preventDefault()
    event.stopPropagation()
    if (this.hasSendTarget && !this.sendTarget.disabled) this.element.requestSubmit(this.sendTarget)
  }

  // Send pressed (or Mod+Enter) while To, Cc and Bcc hold nothing: no token, and nothing
  // typed that would become one (the recipient fields make tokens of it as the form goes)
  _sendsToNobody(submitter) {
    if (submitter && (submitter.hasAttribute("formaction") || !(this.hasSendTarget && submitter === this.sendTarget))) return false

    const fields = this.element.querySelectorAll("input[type='hidden'][name='to'], input[type='hidden'][name='cc'], input[type='hidden'][name='bcc'], [data-recipients-target='input']")
    return Array.from(fields).every((field) => !(field instanceof HTMLInputElement) || field.value.trim() === "")
  }

    // A send that failed comes back to this same form (a morph), which still holds the message
  submitEnded(event) {
    if (event.detail.success) return
    this._submitting = false
    // A save left behind by Send that lands from now on is this form's draft again
    this._discarded = false
  }

  // The form saved as its draft, to the address Save Draft sends it to, as JSON: a new
  // draft the first time, that same draft from then on. Files picked in the form aren't
  // sent along (they go with Send, or with Save Draft), and the draft's copy on the mail
  // server follows a while later (autosave, SyncDraftJob).
  _save() {
    clearTimeout(this._saveTimer)
    if (this._submitting || this._isGone() || !this.draftsUrlValue) return this._saving
    // One at a time: what changes meanwhile is saved after it
    if (this._saving) {
      this._saveAgain = true
      return this._saving
    }

    const form = new FormData(this.element)
    const snapshot = this._formSnapshot(form)
    if (!this._hasUnsaved(snapshot)) return null

    form.delete("attachments[]")
    form.delete("_method")
    form.set("autosave", "1")
    const id = this._draftId()

    this._showStatus(_("Saving…"))
    this._saving = this._send(id ? `${this.draftsUrlValue}/${id}` : this.draftsUrlValue, id ? "PATCH" : "POST", form, snapshot)
      .finally(() => {
        this._saving = null
        if (this._saveAgain) {
          this._saveAgain = false
          this.changed()
        }
      })
    return this._saving
  }

  async _send(url, method, form, snapshot) {
    try {
      // Through Turbo, so the mailbox knows the change it hears of for its own (services/api.js)
      const response = await Turbo.fetch(url, {
        method,
        body: form,
        headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
        // A save on the way out of the page goes on after the page is gone
        keepalive: fitsKeepalive(form)
      })
      // The draft was sent or deleted elsewhere meanwhile
      if (response.status === 404) {
        if (!this._submitting) this._showGone()
        return
      }
      if (!response.ok) throw new Error(`Draft not saved: ${response.status}`)

      const draft = await response.json()
      // Discarded while this save made the draft: the draft goes too
      if (this._discarded) return this._deleteDraft(draft)

      this._adopt(draft)
      this._savedSnapshot = snapshot
      this._showStatus(savedAt(new Date()))
    } catch {
      this._showStatus(_("Not saved"))
      if (!this._submitting) this._saveTimer = setTimeout(() => this._save(), RETRY_DELAY)
    }
  }

  // The form is this draft's from now on, as if it had been opened as the draft: Save Draft
  // and Send go to it, the trash deletes it, and the check above asks after it
  _adopt(draft) {
    if (this._draftId()) return

    const field = document.createElement("input")
    field.type = "hidden"
    field.name = "draft_id"
    field.value = draft.id
    field.dataset.composeTarget = "draftId"
    this.element.prepend(field)
    this.draftUrlValue = `${this.mailsUrlValue}/${draft.id}.json`

    if (this.hasSaveDraftTarget) {
      this.saveDraftTarget.formAction = `${this.draftsUrlValue}/${draft.id}`
      this.saveDraftTarget.name = "_method"
      this.saveDraftTarget.value = "patch"
    }
    if (this.hasDiscardTarget) {
      const trash = this.discardTarget
      trash.href = `${this.mailsUrlValue}/${draft.id}`
      trash.dataset.turboMethod = "delete"
      trash.dataset.turboConfirm = _("Delete this draft?")
      trash.title = _("Delete draft")
      trash.setAttribute("aria-label", _("Delete draft"))
    }
    this._carryOnDraft(draft.attachments || [])
  }

  // The files a forward carries were copied onto the new draft. From now on the form names
  // the draft's copies, as it does for a draft that was opened: taken off, a copy is removed
  // from the draft, and Send doesn't copy them a second time.
  _carryOnDraft(attachments) {
    const claimed = new Set()
    for (const carried of this.element.querySelectorAll("[data-compose-carried]")) {
      const button = carried.querySelector("[data-attachment-id]")
      const field = carried.querySelector("input[name='forward_attachment_ids[]']")
      if (!button || !field || "onDraft" in button.dataset) continue

      const copy = attachments.find(attachment => !claimed.has(attachment.id) &&
        attachment.filename === carried.dataset.filename && String(attachment.file_size) === carried.dataset.fileSize)
      if (!copy) continue

      claimed.add(copy.id)
      field.value = copy.id
      button.dataset.attachmentId = copy.id
      button.dataset.onDraft = "true"
    }
  }

  _draftId() {
    return this.hasDraftIdTarget ? this.draftIdTarget.value : null
  }

  _showStatus(text) {
    if (this.hasSaveStatusTarget) this.saveStatusTarget.textContent = text
  }

  _isGone() {
    return this.hasGoneTarget && !this.goneTarget.hidden
  }

  _showGone() {
    clearTimeout(this._saveTimer)
    this._showStatus("")
    if (!this.hasGoneTarget) return
    this.goneTarget.hidden = false
    this.element.querySelectorAll("button[type='submit']").forEach(button => { button.disabled = true })
  }

  _checkDraft() {
    // Kept for tests, which wait for the check a change started
    this.draftChecked = this._askAfterDraft()
    return this.draftChecked
  }

  async _askAfterDraft() {
    if (!this.draftUrlValue || this._submitting || this._isGone()) return

    let gone
    try {
      const response = await fetch(this.draftUrlValue, { headers: { Accept: "application/json" } })
      if (response.status === 404) {
        gone = true
      } else if (response.ok) {
        // The answer is the draft's conversation: the draft is one of its messages
        const conversation = await response.json()
        const draft = conversation.messages?.find(message => message.id === conversation.id)
        gone = !draft || !draft.draft || draft.trashed
      }
    } catch {
      return
    }
    if (!gone || this._submitting) return

    this._showGone()
  }

  // Whether leaving would lose something: what isn't saved in the draft yet, and files
  // picked in the form, which only Send and Save Draft take along
  _mustAsk() {
    if (this._submitting) return false
    return this.files.length > 0 || this._hasUnsaved(this._formSnapshot())
  }

  _hasUnsaved(snapshot) {
    return hasUnsaved({ current: snapshot, untouched: this._snapshot, saved: this._savedSnapshot, unsent: this.unsentValue })
  }

  // What the form would save. Reading it takes the quote from its frame (addQuote). The
  // files a forward carries count by their number: their ids become the draft's copies'
  // once it is saved (_carryOnDraft), which changes nothing in the mail.
  _formSnapshot(form = new FormData(this.element)) {
    const fields = ["to", "cc", "bcc", "subject", "body", "quoted_message_id", "quote_html"].map(name => form.get(name))
    return JSON.stringify([...fields, form.getAll("forward_attachment_ids[]").length, form.getAll("remove_attachment_ids[]")])
  }

  discard() {
    this._submitting = true // skip confirmation, and saving
    clearTimeout(this._saveTimer)
    // Before the form has a draft, the trash only leaves the page. A first save on its
    // way would make a draft nobody sees: that one is deleted once it is there (_send).
    if (!this._draftId()) this._discarded = true
  }

  // As the trash deletes a draft (Tools::MailsController#destroy). Left alone, the page
  // may be gone by the time it is answered.
  _deleteDraft(draft) {
    return Turbo.fetch(`${this.mailsUrlValue}/${draft.id}`, {
      method: "DELETE",
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      redirect: "manual",
      keepalive: true
    }).catch(() => {})
  }

  // The reply goes out without the mail it answers
  removeQuote() {
    this.quotedMessageTarget.value = ""
    this.quoteTarget.remove()
    this.changed()
  }

  // The quoted mail is changed where it shows: in its frame, which runs no scripts of its
  // own. A frame that was there before this controller has its page already.
  quoteFrameTargetConnected(frame) {
    this._makeQuoteEditable(frame)
  }

  quoteLoaded({ currentTarget }) {
    this._makeQuoteEditable(currentTarget)
  }

  // What the frame holds is what goes out. The form takes it from the frame the moment the
  // form is read (sent, saved, or looked at for changes), so there is no copy of it that can
  // fall behind what shows. A quote nobody touched isn't sent at all: the server quotes the
  // mail as it was written, as it always did.
  addQuote({ formData }) {
    if (!this.hasQuoteFrameTarget || !formData.get("quoted_message_id")) return

    const html = this._quoteHtml()
    if (html === null || html === this._quoteAsLoaded) return

    if (this._quoteIsEmpty()) {
      // Everything taken out of it: there is no quote
      formData.set("quoted_message_id", "")
      formData.delete("quote_html")
    } else {
      formData.set("quote_html", html)
    }
  }

  _makeQuoteEditable(frame) {
    const page = frame.contentDocument
    if (!page?.body) return

    page.body.contentEditable = "true"
    this._quoteAsLoaded = this._quoteHtml()
    // Reaching for the quote is reaching for the form (startEditing), and what happens in a
    // frame isn't heard outside it. Neither is where the keyboard is: a frame doesn't
    // match :focus for what is in it, so the frame says it has the keyboard (mails.css).
    if (!page.compose) {
      for (const type of ["pointerdown", "keydown", "beforeinput"]) {
        page.addEventListener(type, () => page.compose.startEditing(), true)
      }
      // Changed in its frame: the form is saved a moment later, as for any change
      page.addEventListener("input", () => page.compose.changed())
      page.addEventListener("focusin", () => frame.toggleAttribute("data-has-keyboard", true))
      page.addEventListener("focusout", () => frame.toggleAttribute("data-has-keyboard", false))
      // Escape lets go of it, as of any field: the keyboard is the page's again
      page.addEventListener("keydown", (event) => { if (event.key === "Escape") frame.blur() })
      // Cmd+Enter sends from the quote too
      page.addEventListener("keydown", (event) => page.compose.sendWithKeys(event), true)
    }
    page.compose = this
  }

  // The quote as it goes out: a picture by the address it is sent with (data-src,
  // Mails::Quote#to_editable_html), not by the one it shows with here
  _quoteHtml() {
    const body = this.hasQuoteFrameTarget && this.quoteFrameTarget.contentDocument?.body
    if (!body) return null

    const copy = body.cloneNode(true)
    for (const picture of copy.querySelectorAll("img[data-src]")) {
      picture.setAttribute("src", picture.dataset.src)
      picture.removeAttribute("data-src")
    }
    return copy.innerHTML
  }

  _quoteIsEmpty() {
    const body = this.quoteFrameTarget.contentDocument.body
    return !body.textContent.trim() && !body.querySelector("img, table, hr")
  }

  // Cc and Bcc wait behind their buttons in the To field until they're wanted
  showField({ currentTarget, params: { field } }) {
    const target = this[`${field}FieldTarget`]
    target.classList.remove("hidden")
    target.querySelector("input[type=text]")?.focus()
    currentTarget.remove()
  }

  // Picking files again replaces what the input holds, so put back the ones picked before
  handleFiles(event) {
    const newFiles = Array.from(event.target.files)
    this.files.push(...newFiles)
    this.renderAttachments()
    this.updateFileInput()
  }

  removeFile(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.files.splice(index, 1)
    this.renderAttachments()
    this.updateFileInput()
  }

  // A file the mail carries (forwarded, or the draft's own) taken off: it no longer
  // goes along, and a draft's own is removed from the draft when the form is sent
  removeCarried(event) {
    const button = event.currentTarget
    const carried = button.closest("[data-compose-carried]")
    if ("onDraft" in button.dataset) {
      const removed = document.createElement("input")
      removed.type = "hidden"
      removed.name = "remove_attachment_ids[]"
      removed.value = button.dataset.attachmentId
      carried.closest("form").append(removed)
    }
    const list = carried.parentElement
    carried.remove()
    if (!list.children.length) list.remove()
    this.changed()
  }

  renderAttachments() {
    if (!this.hasAttachmentsListTarget) return

    this.attachmentsListTarget.replaceChildren(...this.files.map((file, index) => this.attachmentItem(file, index)))
  }

  // Built with DOM APIs, so a file's name is always text, never markup
  attachmentItem(file, index) {
    const item = document.createElement("div")
    item.className = "compose-attachment-item"
    item.insertAdjacentHTML("afterbegin", FILE_ICON)

    const name = document.createElement("span")
    name.textContent = this.truncateName(file.name, 20)

    const size = document.createElement("span")
    size.className = "compose-attachment-size"
    size.textContent = formatFileSize(file.size)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "compose-attachment-remove"
    remove.dataset.index = index
    remove.dataset.action = "click->compose#removeFile"
    remove.textContent = "×"

    item.append(name, size, remove)
    return item
  }

  updateFileInput() {
    const dt = new DataTransfer()
    this.files.forEach(file => dt.items.add(file))
    if (this.hasFileInputTarget) {
      this.fileInputTarget.files = dt.files
    }
  }

  truncateName(str, length) {
    if (str.length <= length) return str
    const parts = str.split(".")
    const ext = parts.length > 1 ? parts.pop() : ""
    const name = parts.join(".")
    if (ext) {
      const truncatedName = name.slice(0, length - ext.length - 4) + "..."
      return truncatedName + "." + ext
    }
    return str.slice(0, length - 3) + "..."
  }
}
