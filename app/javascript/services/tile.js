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
 * Goes on to another page of the same tool (a folder, a file): in the tile when the
 * view is one, as a visit of the window otherwise
 * @param {Element} element
 * @param {string} url
 */
export function openPage(element, url) {
  const tile = tileOf(element)
  if (!tile) return void Turbo.visit(url)

  const to = new URL(url, window.location.origin)
  tile.setAttribute("src", to.pathname + to.search)
}

/**
 * How much smaller an element is drawn than it is laid out: a tile in the
 * workspace's page is drawn at seven eighths (workspace.css, --tile-zoom). Where an
 * element is on the screen (getBoundingClientRect) is measured as drawn, how far it
 * is scrolled as laid out, so the one is divided by this before it becomes the other.
 * @param {Element} element
 * @returns {number}
 */
export function zoomOf(element) {
  return /** @type {any} */ (element).currentCSSZoom || 1
}

/**
 * How much smaller than laid out an element is drawn at this moment: its zoom, and
 * whatever it is scaled by on top of that. A tile comes in a little smaller than it
 * ends up (workspace.css, workspace-tile-in), and a page that is there quickly
 * measures while it does: by the zoom alone it would scroll a pixel or two short.
 * @param {Element} element a block, which has a width of its own
 * @returns {number}
 */
export function drawnScale(element) {
  const laidOut = parseFloat(getComputedStyle(element).width)
  return laidOut ? element.getBoundingClientRect().width / laidOut : zoomOf(element)
}

/**
 * A distance to scroll by, brought to a whole pixel of the screen. In a tile nine
 * hours of a week are 472 and a half of them, and the browser draws that on the
 * pixel before or the one after by what was left over in the arithmetic.
 * @param {number} distance as laid out
 * @param {Element} element what is scrolled
 * @returns {number}
 */
export function onWholePixel(distance, element) {
  const zoom = zoomOf(element)
  // (to a sixty-fourth first, which is what a page is laid out in: the rest is noise)
  return Math.floor((Math.round(distance * 64) / 64) * zoom) / zoom
}

/**
 * Loads the page again from nothing: for a page that can't be laid over itself (an
 * editor that has to start again)
 * @param {Element} element
 */
export function reloadPage(element) {
  const tile = /** @type {any} */ (tileOf(element))
  if (!tile) return void Turbo.visit(window.location.href, { action: "replace" })

  tile.replaceChildren()
  tile.reload()
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
  const here = pageAddress(element)
  // (the same address again loads nothing by itself; the frame has it as a path or
  // in full, and a reload is what lays the new page over the old one)
  here.pathname + here.search === path ? /** @type {any} */ (tile).reload() : tile.setAttribute("src", path)
}
