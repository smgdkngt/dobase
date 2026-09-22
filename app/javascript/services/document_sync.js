import consumer from "channels/consumer"
import { Y, Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from "rhino-editor"

// Keeps one Yjs document in step with everyone else's through Action Cable.
//
// Yjs merges concurrent edits by itself; all this has to do is carry the bytes.
// Changes go both ways as base64, cursors ride along the same wire under their
// own message, and each page ignores what it sent itself.
//
// The server keeps the changes but cannot merge them — only a browser can. When
// it says the pile has grown, the page that hears it sends the whole document
// back as one change, which replaces the pile.
// Typing makes a change per keystroke. They go out merged, a few at a time:
// Action Cable writes every message to the database here, and a sentence is
// worth one row, not forty.
const SEND_EVERY_MS = 250

export class DocumentSync {
  constructor(documentId, { onSynced } = {}) {
    this.doc = new Y.Doc()
    this.awareness = new Awareness(this.doc)
    this.origin = Math.random().toString(36).slice(2)
    this.onSynced = onSynced
    this.synced = false

    this.pending = []
    this.doc.on("update", (update, origin) => {
      // A change that arrived from someone else is not ours to send back
      if (origin === this) return
      this.queue(update)
    })

    this.awareness.on("update", ({ added, updated, removed }, origin) => {
      // Only our own caret goes out; everyone sends their own
      if (origin === this) return
      const changed = added.concat(updated, removed)
      if (changed.length === 0) return
      this.send("move_caret", { awareness: encode(encodeAwarenessUpdate(this.awareness, changed)) })
    })

    this.channel = consumer.subscriptions.create(
      { channel: "DocumentSyncChannel", document_id: documentId },
      { received: (data) => this.receive(data) }
    )

    this.beforeUnload = () => {
      this.flush()
      this.forgetMyCaret()
    }
    window.addEventListener("beforeunload", this.beforeUnload)
  }

  queue(update) {
    this.pending.push(update)
    this.flushTimer ||= setTimeout(() => this.flush(), SEND_EVERY_MS)
  }

  flush() {
    clearTimeout(this.flushTimer)
    this.flushTimer = null
    if (this.pending.length === 0) return

    const merged = this.pending.length === 1 ? this.pending[0] : Y.mergeUpdates(this.pending)
    this.pending = []
    this.send("apply_update", { update: encode(merged) })
  }

  destroy() {
    this.flush()
    window.removeEventListener("beforeunload", this.beforeUnload)
    this.forgetMyCaret()
    this.channel?.unsubscribe()
    this.awareness.destroy()
    this.doc.destroy()
  }

  // Who you are on everyone else's screen: the name and colour beside a caret
  describeMe(user) {
    this.awareness.setLocalStateField("user", user)
  }

  send(action, payload) {
    this.channel?.perform(action, { ...payload, origin: this.origin })
  }

  receive(data) {
    switch (data.type) {
      case "sync":
        this.applyStored(data)
        break
      case "update":
        if (data.origin === this.origin) return
        Y.applyUpdate(this.doc, decode(data.update), this)
        break
      case "awareness":
        if (data.origin === this.origin) return
        applyAwarenessUpdate(this.awareness, decode(data.awareness), this)
        // Someone who just arrived knows nobody's caret yet, and a caret that
        // stands still isn't sent again for a while
        if (data.hello) this.sendMyCaret()
        break
    }
  }

  applyStored(data) {
    this.doc.transact(() => {
      (data.updates || []).forEach((update) => {
        const bytes = decode(update)
        if (bytes.length > 0) Y.applyUpdate(this.doc, bytes, this)
      })
    }, this)

    this.synced = true
    this.sendMyCaret({ hello: true })
    // A document nobody has opened since this was built starts from the text as
    // it was last saved; every later page joins the copy that page made.
    this.onSynced?.({ seed: data.seed, compact: data.compact })
  }

  // Folds every stored change into one, which is all the server keeps afterwards
  compact() {
    if (!this.synced) return

    this.send("merge_updates", { snapshot: encode(Y.encodeStateAsUpdate(this.doc)) })
  }

  sendMyCaret({ hello = false } = {}) {
    if (!this.awareness.getLocalState()) return

    const awareness = encode(encodeAwarenessUpdate(this.awareness, [ this.doc.clientID ]))
    this.send("move_caret", hello ? { awareness, hello: "1" } : { awareness })
  }

  forgetMyCaret() {
    removeAwarenessStates(this.awareness, [ this.doc.clientID ], "left")
  }
}

function encode(bytes) {
  let binary = ""
  bytes.forEach((byte) => { binary += String.fromCharCode(byte) })
  return btoa(binary)
}

function decode(value) {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index)
  return bytes
}
