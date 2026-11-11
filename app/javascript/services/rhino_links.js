import { addressAtStart, hrefFor, madeByItsText } from "services/link_text"

// A link that an address typed or pasted in an editor became goes where its text
// says, also once the text changes. TipTap's link grows over what is typed right
// after it and keeps its first address: "…/feed.csv" pasted, "?token=abc" typed
// after it, showed the whole address and went to "…/feed.csv", and a word typed
// after the space became part of the link too. After every change the paragraphs
// it touched are put right: such a link covers the whole address that starts
// where it starts (querystring and all, up to a space) and goes there.
// A link put on words of their own (Cmd+K on "the feed") is left alone.

const fixed = new WeakSet()

// Every <rhino-editor> in the app; an editor that is built again gets it again
document.addEventListener("rhino-initialize", event => keepLinksWhole(event.target))
document.addEventListener("rhino-focus", event => keepLinksWhole(event.target))
document.addEventListener("rhino-change", event => keepLinksWhole(event.target))

/** @param {any} element a <rhino-editor> */
export function keepLinksWhole(element) {
  const editor = element?.editor
  if (!editor || editor.isDestroyed || fixed.has(editor)) return
  const linkType = editor.schema.marks.link
  if (!linkType) return

  fixed.add(editor)
  // rhino-editor's bundle doesn't export ProseMirror's Plugin; every plugin of the editor is one
  const Plugin = editor.state.plugins[0].constructor
  editor.registerPlugin(new Plugin({
    appendTransaction: (transactions, _oldState, state) => {
      if (!transactions.some(transaction => transaction.docChanged)) return null
      const tr = state.tr
      for (const position of changedPositions(transactions, state)) {
        const $position = state.doc.resolve(position)
        const block = $position.parent
        if (block.isTextblock) mendLinks(tr, block, $position.start(), linkType)
      }
      return tr.docChanged || tr.steps.length ? tr : null
    }
  }))
}

// Where in the new document the transactions changed something
function changedPositions(transactions, state) {
  const positions = new Set()
  transactions.forEach((transaction, index) => {
    transaction.mapping.maps.forEach((map, mapIndex) => {
      map.forEach((_oldStart, _oldEnd, newStart, newEnd) => {
        // Through the rest of this transaction and the ones after it
        let from = newStart, to = newEnd
        for (const later of transaction.mapping.maps.slice(mapIndex + 1)) { from = later.map(from, -1); to = later.map(to, 1) }
        for (const next of transactions.slice(index + 1)) { from = next.mapping.map(from, -1); to = next.mapping.map(to, 1) }
        positions.add(Math.min(Math.max(from, 0), state.doc.content.size))
        positions.add(Math.min(Math.max(to, 0), state.doc.content.size))
      })
    })
  })
  return positions
}

function mendLinks(tr, block, start, linkType) {
  // One character per position: what isn't text (a line break, a mention) ends an address
  let text = ""
  block.forEach(child => { text += child.isText ? child.text : "￼".repeat(child.nodeSize) })
  let offset = 0
  const runs = []
  block.forEach(child => {
    const mark = linkType.isInSet(child.marks)
    const last = runs[runs.length - 1]
    if (mark && last && last.mark.eq(mark) && last.to === offset) {
      last.to = offset + child.nodeSize
    } else if (mark) {
      runs.push({ mark, from: offset, to: offset + child.nodeSize })
    }
    offset += child.nodeSize
  })

  runs.forEach((run, index) => {
    const href = run.mark.attrs.href || ""
    const runText = text.slice(run.from, run.to)
    if (!madeByItsText(runText, href)) return

    // The address runs on over plain text after the link, never into the next link
    const until = runs[index + 1]?.from ?? text.length
    const address = addressAtStart(text.slice(run.from, until))
    const end = run.from + address.length
    const wanted = hrefFor(address)
    if (end === run.to && wanted === href) return

    tr.removeMark(start + run.from, start + Math.max(run.to, end), linkType)
    tr.addMark(start + run.from, start + end, linkType.create({ ...run.mark.attrs, href: wanted }))
  })
}
