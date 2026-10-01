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
// Someone reading along sends nothing, and still has the document open. The
// server takes five minutes of silence for having left.
const STILL_HERE_EVERY_MS = 60000

export class DocumentSync {
  constructor(documentId, { onSynced, onRefused, onReplaced } = {}) {
    this.doc = new Y.Doc()
    this.awareness = new Awareness(this.doc)
    this.origin = Math.random().toString(36).slice(2)
    this.onSynced = onSynced
    this.onRefused = onRefused
    this.onReplaced = onReplaced
    this.synced = false
    this.replaced = false
    // The newest copy this page has heard of; the one it joined is `generation`
    this.newest = 0

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

    this.stillHere = setInterval(() => this.send("still_here"), STILL_HERE_EVERY_MS)

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
    clearInterval(this.stillHere)
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
    if (this.replaced) return

    this.channel?.perform(action, { ...payload, origin: this.origin })
  }

  receive(data) {
    if (this.replaced) return

    switch (data.type) {
      case "sync":
        // Back after the line was down, to find another copy than the one this
        // page has: the text was replaced while it was away
        if (this.synced && data.generation !== this.generation) return this.startOver()

        this.generation = data.generation
        this.upto = data.upto
        if (this.outdated()) return this.startOver()

        this.applyStored(data)
        break
      case "replaced":
        // Everyone hears which copy is the document's now, and a page that
        // joined that very one has nothing to do. Said to this page alone, about
        // a change it sent, there is no number: its copy is gone.
        this.newest = Math.max(this.newest, data.generation ?? Infinity)
        if (this.synced && this.outdated()) this.startOver()
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
      case "refused":
        this.onRefused?.(data.reason)
        break
    }
  }

  applyStored(data) {
    const stored = (data.updates || []).map(decode).filter((bytes) => bytes.length > 0)
    const back = this.synced

    this.doc.transact(() => {
      stored.forEach((bytes) => Y.applyUpdate(this.doc, bytes, this))
    }, this)

    this.synced = true
    this.sendMyCaret({ hello: true })
    if (back) return this.sendWhatWasMissed(stored)

    // A document nobody has opened since this was built starts from the text as
    // it was last saved; every later page joins the copy that page made.
    this.onSynced?.({ seed: data.seed, compact: data.compact })
  }

  // The line was down and is back. What this page wrote in the meantime was
  // sent into nothing, and everything it writes from here builds on that: the
  // others, and whoever opens the document later, could make nothing of it.
  // Yjs can tell what the stored copy lacks, so that goes out now.
  sendWhatWasMissed(stored) {
    const theirs = new Y.Doc()
    stored.forEach((bytes) => Y.applyUpdate(theirs, bytes))
    const missed = Y.equalSnapshots(Y.snapshot(theirs), Y.snapshot(this.doc))
      ? null
      : Y.encodeStateAsUpdate(this.doc, Y.encodeStateVector(theirs))
    theirs.destroy()

    if (missed) this.send("apply_update", { update: encode(missed) })
  }

  // The copy this page writes in was thrown away: the text was replaced from
  // outside the editor, or the page that was to build the copy left before it
  // had. Nothing more goes out or comes in — a change to a copy that is gone
  // fits nowhere — and the page opens the document again.
  startOver() {
    this.abandon()
    this.onReplaced?.()
  }

  outdated() {
    return this.generation < this.newest
  }

  abandon() {
    this.replaced = true
    this.pending = []
    clearTimeout(this.flushTimer)
    this.flushTimer = null
  }

  // Folds every stored change into one, which replaces them on the server — as
  // far as this page had read them; a change that came in since is kept beside it
  compact() {
    if (!this.synced) return

    this.send("merge_updates", { snapshot: encode(Y.encodeStateAsUpdate(this.doc)), upto: this.upto })
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
