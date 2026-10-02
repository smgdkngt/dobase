// Sends a page to where it belongs for the width of the window, before it is drawn.
// A plain script in the <head> (layouts/application), not a module: those wait for
// the page, and this is about not showing the wrong one first.
//
//   data-wide:   where a window wide enough for tiles goes instead (a tool opened by
//                its address becomes a tile in the workspace)
//   data-narrow: where a window too narrow for tiles goes instead (the workspace
//                hands over to the tool you were on there, kept under data-storage-key)
//
// Turbo runs it again for a page it brings in, which an inline script would not
// survive: its nonce is the page's, and the policy is the first page's.
(() => {
  const gate = document.currentScript
  if (!gate || window.self !== window.top) return

  const { wide, narrow, storageKey } = gate.dataset
  const tiles = window.matchMedia("(min-width: 1024px)").matches

  if (wide && tiles) return window.location.replace(wide)
  if (!narrow || tiles) return

  let to = narrow
  try {
    const kept = JSON.parse(localStorage.getItem(storageKey))
    const tile = kept.tiles[kept.desks[kept.desk].focus]
    if (/^\/tools\/\d+/.test(tile.url)) to = tile.url
  } catch {
    // Nothing kept, or nothing readable: the start page for one tool at a time
  }
  window.location.replace(to)
})()
