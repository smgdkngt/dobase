import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { recentlyReportedContext } from "services/presence"

// Who else is in this tool right now, and what they have open.
//
// Everyone announces themselves on arrival and every half minute after that.
// Anyone who hasn't been heard from in a minute and a half is dropped, so a
// browser that was closed without warning fades out instead of lingering. What
// someone has open is drawn twice: as a line under their face in the topbar,
// and as a ring around the card, item or file itself.
const HEARTBEAT_MS = 30000
const FORGET_AFTER_MS = 90000
// "Anna is typing" lasts this long after the last keystroke anyone heard
const TYPING_SHOWS_FOR_MS = 4000
// And a page says it at most this often while someone keeps typing
const TYPING_SAYS_EVERY_MS = 2000

export default class extends Controller {
  static targets = ["facepile", "watchers", "typing"]
  static values = {
    toolId: Number,
    userId: Number,
    context: String
  }

  connect() {
    this.people = new Map()
    this.typists = new Map() // context -> Map(user id -> { name, until })
    // A page that opened straight onto a card said so before this controller
    // was here to hear it
    this.contextValue = this.contextValue || recentlyReportedContext()
    this.subscribe()
    this.heartbeat = setInterval(() => this.beat(), HEARTBEAT_MS)
    this._onContext = (event) => this.setContext(event.detail?.context)
    window.addEventListener("presence:context", this._onContext)
    // A morph refresh or a frame swap draws the page from the server again,
    // which takes the rings and faces with it
    this._onRedraw = () => this.render()
    document.addEventListener("turbo:morph", this._onRedraw)
    document.addEventListener("turbo:frame-render", this._onRedraw)
  }

  disconnect() {
    clearInterval(this.heartbeat)
    clearTimeout(this.typingSweep)
    window.removeEventListener("presence:context", this._onContext)
    document.removeEventListener("turbo:morph", this._onRedraw)
    document.removeEventListener("turbo:frame-render", this._onRedraw)
    this.channel?.unsubscribe()
    this.channel = null
  }

  subscribe() {
    this.channel = consumer.subscriptions.create(
      { channel: "PresenceChannel", tool_id: this.toolIdValue },
      {
        received: (data) => this.receive(data),
        connected: () => this.announce({ hello: true })
      }
    )
  }

  // What this page is looking at, as a type and an id: "card:12", "board".
  // Pages say so by dispatching presence:context on the window.
  setContext(context) {
    const next = context || ""
    if (next === this.contextValue) return

    this.contextValue = next
    this.announce()
  }

  announce(options = {}) {
    this.channel?.perform("announce", { context: this.contextValue, hello: options.hello ? "1" : "", at: Date.now() })
  }

  beat() {
    this.announce()
    this.forgetTheQuiet()
  }

  receive(data) {
    // A sidebar somewhere asks who is on this tool; say so, as to a hello
    if (data.type === "roll_call") {
      this.answer()
      return
    }

    // Our own arrival tells us nothing we don't know
    if (!data.user || data.user.id === this.userIdValue) return

    switch (data.type) {
      case "here":
        // An older word from a page they have since left says nothing new, and
        // an undated one can't say it's newer than what we have
        if (this.people.get(data.user.id)?.at > (data.at || 0)) return
        this.people.set(data.user.id, { ...data.user, context: data.context, at: data.at, seenAt: Date.now() })
        if (data.hello) this.answer()
        break
      case "gone":
        this.people.delete(data.user.id)
        this.typists.forEach((people) => people.delete(data.user.id))
        break
      case "typing":
        this.heardTyping(data)
        return
      default:
        return
    }

    this.render()
  }

  answer() {
    this.channel?.perform("answer", { context: this.contextValue, at: Date.now() })
  }

  forgetTheQuiet() {
    const cutoff = Date.now() - FORGET_AFTER_MS
    let dropped = false

    this.people.forEach((person, id) => {
      if (person.seenAt < cutoff) {
        this.people.delete(id)
        dropped = true
      }
    })

    if (dropped) this.render()
  }

  render() {
    this.renderFacepile()
    this.renderItems()
    this.watchersTargets.forEach((slot) => this.renderWatchers(slot))
  }

  // Keystrokes in a comment box: data-action="keydown->presence#typing" with
  // data-presence-context-param="card:12" on the element around it
  typing(event) {
    const context = event.params.context
    const now = Date.now()
    if (!context || (this.lastTypingSent?.context === context && now - this.lastTypingSent.at < TYPING_SAYS_EVERY_MS)) return

    this.lastTypingSent = { context, at: now }
    this.channel?.perform("typing", { context })
  }

  heardTyping(data) {
    if (!data.context) return

    if (!this.typists.has(data.context)) this.typists.set(data.context, new Map())
    this.typists.get(data.context).set(data.user.id, { name: data.user.name, until: Date.now() + TYPING_SHOWS_FOR_MS })
    this.typingTargets.forEach((slot) => this.renderTyping(slot))

    clearTimeout(this.typingSweep)
    this.typingSweep = setTimeout(() => this.typingTargets.forEach((slot) => this.renderTyping(slot)), TYPING_SHOWS_FOR_MS + 100)
  }

  renderTyping(slot) {
    const now = Date.now()
    const people = this.typists.get(slot.dataset.presenceFor) || new Map()
    people.forEach((typist, id) => { if (typist.until < now) people.delete(id) })

    const names = Array.from(people.values()).map((typist) => typist.name)
    slot.textContent = names.length === 0 ? ""
      : names.length === 1 ? `${names[0]} is writing a comment…`
      : `${names.length} people are writing comments…`
    slot.hidden = names.length === 0
  }

  typingTargetConnected(slot) {
    if (this.typists) this.renderTyping(slot)
  }

  // A card or todo dialog arrives after the page does, fetched when it opens
  watchersTargetConnected(slot) {
    if (this.people) this.renderWatchers(slot)
  }

  // Inside an open card, todo or document: the others who have it open too
  renderWatchers(slot) {
    const people = Array.from(this.people.values())
      .filter((person) => person.context === slot.dataset.presenceFor)
      .sort((a, b) => a.name.localeCompare(b.name))

    slot.replaceChildren(...people.map((person) => this.faceFor(person)))
    if (people.length > 0) {
      const label = document.createElement("span")
      label.className = "presence-watchers-label"
      label.textContent = people.length === 1 ? `${people[0].name} is here too` : `${people.length} others are here too`
      slot.appendChild(label)
    }
    slot.hidden = people.length === 0
  }

  renderFacepile() {
    if (!this.hasFacepileTarget) return

    const people = Array.from(this.people.values()).sort((a, b) => a.name.localeCompare(b.name))
    this.facepileTarget.replaceChildren(...people.map((person) => this.faceFor(person)))
    this.facepileTarget.classList.toggle("hidden", people.length === 0)
  }

  faceFor(person) {
    const face = document.createElement("span")
    face.className = "presence-face avatar avatar-sm"
    face.title = person.name
    face.setAttribute("aria-label", `${person.name} is here`)

    if (person.avatar_url) {
      const image = document.createElement("img")
      image.src = person.avatar_url
      image.alt = ""
      image.className = "w-full h-full object-cover"
      face.appendChild(image)
    } else {
      const initials = document.createElement("span")
      initials.textContent = person.initials
      face.appendChild(initials)
    }

    return face
  }

  // A ring on the card, item or file someone else has open, with their initials
  // in the corner. Items say what they are with data-presence-item="card:12".
  renderItems() {
    const here = new Map()
    this.people.forEach((person) => {
      if (!person.context) return
      const at = here.get(person.context) || []
      at.push(person)
      here.set(person.context, at)
    })

    this.element.querySelectorAll("[data-presence-item]").forEach((item) => {
      const people = here.get(item.dataset.presenceItem)
      item.classList.toggle("presence-here", Boolean(people))
      const existing = item.querySelector("[data-presence-badge]")
      existing?.remove()
      if (!people) return

      const badge = document.createElement("span")
      badge.dataset.presenceBadge = ""
      badge.className = "presence-badge"
      badge.textContent = people.map((person) => person.initials).join(" ")
      badge.title = `${people.map((person) => person.name).join(", ")} ${people.length === 1 ? "is" : "are"} looking at this`
      item.appendChild(badge)
    })
  }
}
