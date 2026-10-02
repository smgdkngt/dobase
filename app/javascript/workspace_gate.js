// Sends a page to where it belongs for the width of the window, before it is drawn.
// A plain script in the <head> (layouts/application), not a module: those wait for
// the page, and this is about not showing the wrong one first.
//
//   data-wide:   where a window wide enough for tiles goes instead (a tool opened by
//                its address becomes a tile in the workspace)
//   data-narrow: where a window too narrow for tiles goes instead (the workspace
//                hands over to the tool you were on there, kept under data-storage-key,
//                when it is still one of yours: their ids are in data-tools)
//
// Turbo runs it again for a page it brings in, which an inline script would not
// survive: its nonce is the page's, and the policy is the first page's.
(() => {
  const gate = document.currentScript
  if (!gate || window.self !== window.top) return

  const { wide, narrow, storageKey, tools = "" } = gate.dataset
  const tiles = window.matchMedia("(min-width: 1024px)").matches

  if (wide && tiles) return window.location.replace(wide)
  if (!narrow || tiles) return

  // A tile's page can be gone (its tool deleted, or no longer yours): that page sends
  // you to the start, and the start sends a browser like this one back here. Here
  // again within a moment means that happened: the tile is forgotten, and the start
  // page for one tool at a time finds a page that exists.
  const HANDED_OVER = "dobase:workspace:handed-over"
  let again = false
  try {
    again = Date.now() - Number(sessionStorage.getItem(HANDED_OVER)) < 10000
    sessionStorage.setItem(HANDED_OVER, Date.now())
  } catch {
    // No storage to remember it in: the tile's page it is
  }

  let to = narrow
  try {
    const kept = JSON.parse(localStorage.getItem(storageKey))
    const focus = kept.desks[kept.desk].focus
    if (again) {
      delete kept.tiles[focus]
      localStorage.setItem(storageKey, JSON.stringify(kept))
    } else if (tools.split(" ").includes(kept.tiles[focus].url.match(/^\/tools\/(\d+)/)?.[1])) {
      to = kept.tiles[focus].url
    }
  } catch {
    // Nothing kept, or nothing readable: the start page for one tool at a time
  }
  window.location.replace(to)
})()
