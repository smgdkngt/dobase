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
export class DocumentSync {
  constructor(documentId, { onSynced } = {}) {
    this.doc = new Y.Doc()
    this.awareness = new Awareness(this.doc)
    this.origin = Math.random().toString(36).slice(2)
    this.onSynced = onSynced
    this.synced = false

    this.doc.on("update", (update, origin) => {
      // A change that arrived from someone else is not ours to send back
      if (origin === this) return
      this.send("apply_update", { update: encode(update) })
    })

    this.awareness.on("update", ({ added, updated, removed }) => {
      const changed = added.concat(updated, removed)
      if (changed.length === 0) return
      this.send("move_caret", { awareness: encode(encodeAwarenessUpdate(this.awareness, changed)) })
    })

    this.channel = consumer.subscriptions.create(
      { channel: "DocumentSyncChannel", document_id: documentId },
      { received: (data) => this.receive(data) }
    )

    this.beforeUnload = () => this.forgetMyCaret()
    window.addEventListener("beforeunload", this.beforeUnload)
  }

  destroy() {
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
    // A document nobody has opened since this was built starts from the text as
    // it was last saved; every later page joins the copy that page made.
    this.onSynced?.({ seed: data.seed, compact: data.compact })
  }

  // Folds every stored change into one, which is all the server keeps afterwards
  compact() {
    if (!this.synced) return

    this.send("merge_updates", { snapshot: encode(Y.encodeStateAsUpdate(this.doc)) })
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
