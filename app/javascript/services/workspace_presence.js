import consumer from "channels/consumer"

// Who is in which tool, across the whole workspace, for the sidebar.
//
// One subscription for the life of the page, not one per visit: the sidebar is
// drawn again on every Turbo navigation, and a fresh subscription each time
// would ask every colleague in every tool to answer a roll call per click. The
// sidebar controller reads from here and redraws when it changes.
const FORGET_AFTER_MS = 90000

class WorkspacePresence {
  constructor(userId) {
    this.userId = userId
    this.byTool = new Map() // tool id -> Map(user id -> person)
    this.listeners = new Set()

    this.channel = consumer.subscriptions.create(
      { channel: "WorkspacePresenceChannel" },
      {
        connected: () => this.channel.perform("roll_call", {}),
        received: (data) => this.receive(data)
      }
    )
    this.sweeper = setInterval(() => this.forgetTheQuiet(), FORGET_AFTER_MS / 3)
  }

  receive(data) {
    if (!data.tool_id || !data.user || data.user.id === this.userId) return

    const toolId = Number(data.tool_id)
    if (data.type === "gone") {
      this.byTool.get(toolId)?.delete(data.user.id)
    } else if (data.type === "here") {
      // Arriving somewhere means leaving wherever the sidebar last saw them
      this.byTool.forEach((people, id) => { if (id !== toolId) people.delete(data.user.id) })
      if (!this.byTool.has(toolId)) this.byTool.set(toolId, new Map())
      this.byTool.get(toolId).set(data.user.id, { ...data.user, seenAt: Date.now() })
    } else {
      return
    }

    this.changed()
  }

  forgetTheQuiet() {
    const cutoff = Date.now() - FORGET_AFTER_MS
    let dropped = false

    this.byTool.forEach((people) => {
      people.forEach((person, id) => {
        if (person.seenAt < cutoff) {
          people.delete(id)
          dropped = true
        }
      })
    })

    if (dropped) this.changed()
  }

  peopleIn(toolId) {
    return Array.from(this.byTool.get(Number(toolId))?.values() || [])
      .sort((a, b) => a.name.localeCompare(b.name))
  }

  subscribe(listener) {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  changed() {
    this.listeners.forEach((listener) => listener())
  }
}

let instance = null

// The one shared list for this page. A different user (signing out and in
// again without a reload) starts a fresh one.
export function workspacePresence(userId) {
  if (instance && instance.userId !== userId) {
    instance.channel.unsubscribe()
    clearInterval(instance.sweeper)
    instance = null
  }
  instance ||= new WorkspacePresence(userId)
  return instance
}
