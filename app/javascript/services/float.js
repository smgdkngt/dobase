// A dialog that floats over the workspace.
//
// A tile is a frame, and nothing in a frame can lie outside it: a card's details
// opened in a narrow tile would be squeezed into that tile. So the big dialogs (a
// card, a todo, an event) are opened the way a window manager opens a dialog over
// tiled windows: floating, in the middle, over all of them.
//
// What floats is the tool's own page once more, in a frame as large as the window
// that shows nothing but its dialog (workspace.css, <html data-floating>): the page
// is asked for with the address that opens the dialog by itself (?card=12), so every
// button in it works as it does anywhere. When the dialog closes the frame goes, and
// the tile it came from is drawn again (workspace_controller.js).
//
// The workspace asks for that page with ?float, and the server then draws nothing
// but the dialog, with the card in it (floating? in ApplicationController): no board
// to draw first and no card to fetch afterwards, which is what made it slow. A page
// the float goes on to (the board after a card is saved) is the whole page, as before.

// Whether this page is such a floating frame
export const floating = window.self !== window.top && window.name === "workspace-float"
// The address it was opened with, which is the one that opens the dialog
export const floatedAt = floating ? window.location.pathname + window.location.search : null

// Whether the server drew `holder` (what a dialog fetches its content into) with
// `id` in it already. Once: what is opened after that is fetched like anywhere.
export function drawnWith(holder, id) {
  if (holder?.dataset.drawn !== String(id)) return false

  delete holder.dataset.drawn
  return true
}

// From a tile: asks the workspace to float `url`. True when it will, and then the
// tile opens nothing itself. `clear` is the parameter in the tile's own address that
// would open the dialog there (a notification leads to ?card=12): it is taken off, so
// the tile doesn't open the dialog again with every reload.
export function floats(url, { clear } = {}) {
  if (window.self === window.top || window.name !== "workspace-tile") return false

  const here = new URL(window.location.href)
  if (clear && here.searchParams.has(clear)) {
    here.searchParams.delete(clear)
    history.replaceState(history.state, "", here)
    window.parent.postMessage({ tile: "location", url: here.pathname + here.search, title: document.title }, window.location.origin)
  }
  window.parent.postMessage({ tile: "float", url }, window.location.origin)
  return true
}
