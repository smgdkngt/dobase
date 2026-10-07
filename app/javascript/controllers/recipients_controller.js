import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { formatRecipient, inQuotes, listOfRecipients, parseRecipients, validAddress } from "services/recipients"

// A To, Cc or Bcc field of a mail being written (tools/mails/_recipient_field).
//
// Every address is a token, and the tokens in the page are what the field holds: the
// form's hidden field is written from them. A token is dragged to another place or
// another field, or moved there with Shift and the arrows, or from its menu. What is
// typed is looked up among the people the account knows; the list comes from the
// server as it is shown (Tools::Mails::ContactsController).
const ORDER = [ "to", "cc", "bcc" ]

export default class extends Controller {
  static targets = [ "list", "entry", "input", "hidden", "token", "options", "option", "menu", "menuAddress", "status", "template" ]
  static values = { url: String, field: String, label: String }

  connect() {
    this.form = this.element.closest("form")
    // An address typed just before Send or Save Draft goes along with the form
    this._onSubmit = () => this.commit()
    this.form?.addEventListener("submit", this._onSubmit)
    this._onMenu = (event) => this.menuToggled(event)
    this.menuTarget.addEventListener("toggle", this._onMenu)

    this.sortable = Sortable.create(this.listTarget, {
      group: "recipients",
      draggable: "[data-recipients-target~='token']",
      animation: 150,
      // The browser's own dragging doesn't start on a button everywhere
      forceFallback: true,
      fallbackTolerance: 4,
      fallbackOnBody: true,
      ghostClass: "recipient-landing",
      fallbackClass: "recipient-dragged",
      // A finger has to rest on a token first, or a swipe over the field would drag one
      delay: 200,
      delayOnTouchOnly: true,
      onStart: () => this.dragging(true),
      onEnd: ({ item }) => this.letGo(item),
      onAdd: ({ item }) => this.dropped(item),
      onSort: () => this.changed()
    })

    this.close()
    this.changed()
  }

  disconnect() {
    this.form?.removeEventListener("submit", this._onSubmit)
    this.menuTarget.removeEventListener("toggle", this._onMenu)
    this.sortable?.destroy()
    clearTimeout(this.waiting)
  }

  // --- What is typed ---

  typed() {
    clearTimeout(this.waiting)
    const query = this.inputTarget.value.trim()
    if (!query) return this.close()

    this.waiting = setTimeout(() => {
      this.optionsTarget.src = `${this.urlValue}?q=${encodeURIComponent(query)}`
    }, 120)
  }

  // The server's list for what was typed is in
  offered() {
    const have = new Set(this.recipients.map((one) => one.address.toLowerCase()))
    this.optionTargets.forEach((option, index) => {
      if (have.has(option.dataset.address.toLowerCase())) return option.remove()

      option.id = `${this.optionsTarget.id}-${index}`
    })
    if (this.optionTargets.length === 0 || !this.inputTarget.value.trim() || document.activeElement !== this.inputTarget) return this.close()

    this.optionsTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    // The first is the one Enter takes, unless a whole address was typed: that is meant as it is
    this.activate(validAddress(this.inputTarget.value.trim()) ? null : this.optionTargets[0])
    const count = this.optionTargets.length
    this.say(`${count} ${count === 1 ? "suggestion" : "suggestions"}`)
  }

  inputKey(event) {
    const input = this.inputTarget
    const atStart = input.selectionStart === 0 && input.selectionEnd === 0
    const options = this.open ? this.optionTargets : []

    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        if (options.length === 0) return
        event.preventDefault()
        const at = options.indexOf(this.active)
        const next = event.key === "ArrowDown" ? Math.min(at + 1, options.length - 1) : Math.max(at - 1, 0)
        return this.activate(options[next])
      }
      case "Enter":
        // (never the form's: Enter in an address field doesn't send the mail)
        event.preventDefault()
        return this.accept()
      case "Tab":
        // Takes what is typed and goes on to the next field
        if (!event.shiftKey) this.accept()
        return
      case ",":
      case ";":
        if (!input.value.trim() || inQuotes(input.value)) return
        event.preventDefault()
        return this.accept()
      case "Escape":
        if (!this.open) return
        event.preventDefault()
        return this.close()
      case "Backspace":
      case "ArrowLeft":
        // Out of the text and onto the last token: Backspace there takes it away
        if (!atStart || event.shiftKey || this.tokenTargets.length === 0) return
        event.preventDefault()
        return this.focusToken(this.tokenTargets.at(-1))
    }
  }

  pasted(event) {
    const text = event.clipboardData?.getData("text/plain") || ""
    if (this.inputTarget.value.trim() || !listOfRecipients(text)) return

    event.preventDefault()
    const added = parseRecipients(text).filter((recipient) => this.add(recipient))
    this.changed()
    if (added.length > 0) this.say(`${added.length} ${added.length === 1 ? "address" : "addresses"} added to ${this.labelValue}`)
  }

  left() {
    this.commit()
    this.close()
  }

  // A click on the list takes what is offered without the field losing the keyboard
  keepFocus(event) {
    event.preventDefault()
  }

  choose({ currentTarget }) {
    this.pick(currentTarget)
    this.inputTarget.focus()
  }

  focusInput({ target }) {
    if (target === this.listTarget) this.inputTarget.focus()
  }

  // --- Tokens ---

  tokenKey(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return

    const token = this.tokenOf(event.currentTarget)
    const tokens = this.tokenTargets
    const at = tokens.indexOf(token)
    const step = { ArrowLeft: -1, ArrowRight: 1 }[event.key]
    const over = { ArrowUp: -1, ArrowDown: 1 }[event.key]

    if (step && event.shiftKey) {
      // To another place in the field
      event.preventDefault()
      const beside = tokens[at + step]
      if (!beside) return
      this.listTarget.insertBefore(token, step < 0 ? beside : beside.nextSibling)
      this.changed()
      this.focusToken(token)
      this.say(`${this.nameOf(token)}, ${at + step + 1} of ${tokens.length} in ${this.labelValue}`)
    } else if (step) {
      event.preventDefault()
      const beside = tokens[at + step]
      if (beside) this.focusToken(beside)
      else if (step > 0) this.inputTarget.focus()
    } else if (over && event.shiftKey) {
      // To the field above or below
      event.preventDefault()
      const field = ORDER[ORDER.indexOf(this.fieldValue) + over]
      if (field) this.move(token, field)
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      event.currentTarget.click()
    } else if (event.key === "Backspace" || event.key === "Delete") {
      event.preventDefault()
      const next = event.key === "Backspace" ? tokens[at - 1] || tokens[at + 1] : tokens[at + 1]
      this.drop(token)
      next ? this.focusToken(next) : this.inputTarget.focus()
    }
  }

  // The menu is the field's; it opens for the token that was pressed
  menuFor(event) {
    const token = this.tokenOf(event.currentTarget)
    // (let go of after a drag: that was no press)
    if (this.justDragged === token) return event.preventDefault()

    this.current = token
    this.tokenTargets.forEach((one) => one.style.removeProperty("anchor-name"))
    token.style.setProperty("anchor-name", `--${this.menuTarget.id}`)
    this.menuAddressTarget.textContent = formatRecipient(this.read(token))
  }

  menuToggled(event) {
    const open = event.newState === "open"
    this.tokenTargets.forEach((token) => this.button(token).toggleAttribute("data-menu-open", open && token === this.current))
  }

  async copy() {
    const token = this.current
    this.menuTarget.hidePopover()
    try {
      await navigator.clipboard.writeText(token.dataset.address)
      this.say("Address copied")
    } catch {
      this.say("The address could not be copied")
    }
  }

  // Back into the text, to change it
  edit(event) {
    const token = event.currentTarget.closest("[popover]") ? this.current : this.tokenOf(event.currentTarget)
    if (this.menuTarget.matches(":popover-open")) this.menuTarget.hidePopover()
    this.commit()
    this.inputTarget.value = formatRecipient(this.read(token))
    token.remove()
    this.changed()
    this.inputTarget.focus()
  }

  moveTo({ params: { field } }) {
    this.menuTarget.hidePopover()
    this.move(this.current, field)
  }

  remove() {
    this.menuTarget.hidePopover()
    this.drop(this.current)
    this.inputTarget.focus()
  }

  // A token handed over by another field (its menu, or Shift and an arrow)
  receive({ detail: { token } }) {
    this.show()
    const twin = this.tokenFor(token.dataset.address)
    if (twin) token.remove()
    else this.listTarget.insertBefore(token, this.entryTarget)
    this.changed()
    this.focusToken(twin || token)
    this.say(`${this.nameOf(twin || token)} moved to ${this.labelValue}`)
  }

  // --- Dragging ---

  // Cc and Bcc are there to drop on while a token is in the hand
  dragging(on) {
    this.form?.toggleAttribute("data-dragging-recipient", on)
  }

  // Letting go of a token is no press on it: its menu stays shut
  letGo(token) {
    this.dragging(false)
    this.justDragged = token
    setTimeout(() => { this.justDragged = null })
  }

  // A token let go in this field, from another
  dropped(token) {
    this.show()
    const twin = this.tokenTargets.find((one) => one !== token && this.same(one, token.dataset.address))
    if (twin) token.remove()
    this.changed()
    this.say(`${this.nameOf(token)} moved to ${this.labelValue}`)
  }

  // --- What it takes to do those ---

  get recipients() {
    return this.tokenTargets.map((token) => this.read(token))
  }

  get open() {
    return !this.optionsTarget.hidden
  }

  read(token) {
    return { name: token.dataset.name || "", address: token.dataset.address }
  }

  tokenOf(element) {
    return element.closest("[data-recipients-target~='token']")
  }

  tokenFor(address) {
    return this.tokenTargets.find((token) => this.same(token, address))
  }

  same(token, address) {
    return token.dataset.address.toLowerCase() === address.toLowerCase()
  }

  button(token) {
    return token.querySelector("button")
  }

  nameOf(token) {
    return token.dataset.name || token.dataset.address
  }

  focusToken(token) {
    this.button(token).focus()
  }

  // The offered person the arrows are on, or what was typed
  accept() {
    this.active ? this.pick(this.active) : this.commit()
  }

  pick(option) {
    const recipient = { name: option.dataset.name || "", address: option.dataset.address }
    this.inputTarget.value = ""
    this.close()
    if (this.add(recipient)) this.say(`${recipient.name || recipient.address} added to ${this.labelValue}`)
    this.changed()
  }

  commit() {
    const text = this.inputTarget.value
    if (!text.trim()) return

    this.inputTarget.value = ""
    this.close()
    parseRecipients(text).forEach((recipient) => this.add(recipient))
    this.changed()
  }

  // A token for someone, unless the field has them already
  add(recipient) {
    if (this.tokenFor(recipient.address)) return null

    const token = this.templateTarget.content.firstElementChild.cloneNode(true)
    const valid = validAddress(recipient.address)
    token.dataset.address = recipient.address
    token.dataset.name = recipient.name
    token.toggleAttribute("data-invalid", !valid)
    token.querySelector("[data-recipient-part='name']").textContent = recipient.name || recipient.address
    token.querySelector("[data-recipient-part='more']").textContent = valid ? (recipient.name ? `, ${recipient.address}` : "") : ", not a valid address"
    this.button(token).title = recipient.address
    this.listTarget.insertBefore(token, this.entryTarget)
    return token
  }

  drop(token) {
    const name = this.nameOf(token)
    token.remove()
    this.changed()
    this.say(`${name} removed from ${this.labelValue}`)
  }

  move(token, field) {
    const other = this.form?.querySelector(`[data-recipients-field-value='${field}']`)
    if (!other) return

    other.dispatchEvent(new CustomEvent("recipients:take", { detail: { token } }))
    this.changed()
  }

  // The tokens are what the field holds: the form's field is written from them
  changed() {
    // (what is typed stays after the tokens, also for the Tab key)
    if (this.entryTarget.nextElementSibling) this.listTarget.append(this.entryTarget)
    // A token that came from another field opens this one's menu
    this.tokenTargets.forEach((token) => this.button(token).setAttribute("popovertarget", this.menuTarget.id))
    this.hiddenTarget.value = this.recipients.map(formatRecipient).join(", ")
  }

  // Cc and Bcc wait behind their buttons in the To field until something is put in them
  show() {
    if (!this.element.classList.contains("hidden")) return

    const toggle = this.form?.querySelector(`[data-compose-field-param='${this.fieldValue}']`)
    toggle ? toggle.click() : this.element.classList.remove("hidden")
  }

  activate(option) {
    this.optionTargets.forEach((one) => one.setAttribute("aria-selected", String(one === option)))
    this.active = option || null
    if (option) {
      this.inputTarget.setAttribute("aria-activedescendant", option.id)
      option.scrollIntoView({ block: "nearest" })
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  close() {
    clearTimeout(this.waiting)
    this.active = null
    this.optionsTarget.hidden = true
    this.optionsTarget.removeAttribute("src")
    this.optionsTarget.replaceChildren()
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  say(text) {
    this.statusTarget.textContent = text
  }
}
