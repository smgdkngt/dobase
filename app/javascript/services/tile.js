// The page a view is on is a document of its own, or a tile in the workspace's own
// page: a <turbo-frame> (services/tool_frame.js#pageFrame). A view
// that draws its page again, or reads its address, asks here, and gets the tile's
// when it is in one.

/**
 * @param {Element} element
 * @returns {HTMLElement | null}
 */
export function tileOf(element) {
  return element.closest("turbo-frame.tile-frame")
}

/**
 * @param {Element} element
 * @returns {URL}
 */
export function pageAddress(element) {
  return new URL(tileOf(element)?.getAttribute("src") || window.location.href, window.location.origin)
}

/**
 * Goes to another address on the same page (without ?item=12, say), or draws the
 * page again when it is there already
 * @param {Element} element
 * @param {URL | string} [url]
 */
export function visitPage(element, url = pageAddress(element)) {
  const tile = tileOf(element)
  if (!tile) return void Turbo.visit(url.toString(), { action: "replace" })

  const to = new URL(url, window.location.origin)
  const path = to.pathname + to.search
  // (the same address again loads nothing by itself)
  tile.getAttribute("src") === path ? /** @type {any} */ (tile).reload() : tile.setAttribute("src", path)
}
