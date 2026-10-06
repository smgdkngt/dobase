// How the workspace's tiles are arranged (workspace_controller.js), without a page
// to draw them on: a desktop is a binary tree of splits with tiles as its leaves.
// Nothing here touches the page, so it is tried without a browser (test/javascript).
import { pathOf, toolIdOf } from "services/tool_frame"

/**
 * A tile, or a split with a tree in each half.
 * @typedef {{ tile?: string, split?: "row" | "column", ratio?: number, first?: Tree, second?: Tree }} Tree
 * @typedef {{ tree: Tree | null, focus: string | null, alone: boolean, name: string }} Desk
 * @typedef {{ url: string, title: string }} Tile
 * @typedef {{ desk: number, desks: Record<string, Desk>, tiles: Record<string, Tile> }} State
 * @typedef {{ x: number, y: number, width: number, height: number }} Rect
 * @typedef {"left" | "right" | "up" | "down"} Direction
 */

export const GAP = 6
// Dragging a split never leaves a tile narrower or lower than this
export const MIN_TILE = 220
// A new tile only halves one that leaves both halves at least this big
export const ROOM_TO_SPLIT = { width: 340, height: 240 }
export const DESKS = [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ]
// A desktop's name is a word or two beside its number in the bar
export const DESK_NAME_LENGTH = 24
/** @type {State} */
export const NOTHING_OPEN = { desk: 1, desks: {}, tiles: {} }

/**
 * @param {State} state
 * @param {number | string} number
 * @returns {Desk}
 */
export function deskAt(state, number) {
  return (state.desks[number] ||= { tree: null, focus: null, alone: false, name: "" })
}

/**
 * Finds a new tile its place, and says on which desktop that is. It halves the tile
 * you are on, side by side when that is wide and stacked when it is tall. When
 * those halves would be too small it halves the biggest tile that has the room,
 * and when none has, it takes the next desktop with nothing on it.
 * @param {State} state
 * @param {Rect} room
 * @param {number} number
 * @param {string} id
 * @returns {number}
 */
export function insert(state, room, number, id) {
  const desk = deskAt(state, number)
  if (!desk.tree) {
    desk.tree = { tile: id }
    return number
  }

  const rects = place(desk, room).tiles
  const tiles = leaves(desk.tree)
  const candidates = [ desk.focus, ...tiles.sort((a, b) => area(rects.get(b)) - area(rects.get(a))) ]
  for (const target of candidates) {
    const rect = target && rects.get(target)
    const split = rect && splitFor(rect)
    if (!split) continue

    halve(find(desk.tree, target), split, target, id)
    return number
  }

  const free = [ ...Array(9).keys() ].map((index) => (number + index) % 9 + 1).find((other) => !state.desks[other]?.tree)
  if (free) return insert(state, room, free, id)

  // Every desktop is in use and nothing has room: halve the one you are on anyway
  const target = desk.focus && tiles.includes(desk.focus) ? desk.focus : tiles[tiles.length - 1]
  const rect = /** @type {Rect} */ (rects.get(target))
  halve(find(desk.tree, target), rect.height > rect.width ? "column" : "row", target, id)
  return number
}

/**
 * The other half takes the room of both. Returns the tile that is nearest now.
 * @param {Desk} desk
 * @param {string} id
 * @returns {string | null | undefined}
 */
export function remove(desk, id) {
  if (desk.tree?.tile === id) return void (desk.tree = null)

  const parent = parentOf(desk.tree, id)
  if (!parent) return desk.focus

  const other = /** @type {Tree} */ (parent.first?.tile === id ? parent.second : parent.first)
  for (const key of /** @type {(keyof Tree)[]} */ (Object.keys(parent))) delete parent[key]
  Object.assign(parent, other)
  return leaves(parent)[0]
}

/**
 * Where every tile of a desktop goes, and the gaps between them that can be dragged
 * @param {Desk} desk
 * @param {Rect} room
 * @returns {{ tiles: Map<string, Rect>, splits: { node: Tree, room: Rect, rect: Rect }[] }}
 */
export function place(desk, room) {
  /** @type {Map<string, Rect>} */
  const tiles = new Map()
  /** @type {{ node: Tree, room: Rect, rect: Rect }[]} */
  const splits = []

  /** @type {(node: Tree, rect: Rect) => void} */
  const put = (node, rect) => {
    if (node.tile) return void tiles.set(node.tile, rect)

    const along = node.split === "row" ? "width" : "height"
    const from = node.split === "row" ? "x" : "y"
    const size = rect[along] - GAP
    const first = Math.round(size * /** @type {number} */ (node.ratio))

    put(/** @type {Tree} */ (node.first), { ...rect, [along]: first })
    put(/** @type {Tree} */ (node.second), { ...rect, [from]: rect[from] + first + GAP, [along]: size - first })
    splits.push({ node, room: rect, rect: { ...rect, [from]: rect[from] + first, [along]: GAP } })
  }

  if (desk.tree) put(desk.tree, room)
  return { tiles, splits }
}

/**
 * The tile on that side of the one you are on: the nearest, and of those the one
 * that shares the most of that side. Nothing when there is none.
 * @param {Desk} desk
 * @param {Rect} room
 * @param {Direction} direction
 * @returns {string | null}
 */
export function neighbour(desk, room, direction) {
  const rects = place(desk, room).tiles
  const from = desk.focus && rects.get(desk.focus)
  if (!from) return null

  const sideways = direction === "left" || direction === "right"
  /** @type {(rect: Rect) => number} */
  const ahead = (rect) => ({
    left: from.x - (rect.x + rect.width),
    right: rect.x - (from.x + from.width),
    up: from.y - (rect.y + rect.height),
    down: rect.y - (from.y + from.height)
  })[direction]
  /** @type {(rect: Rect) => number} */
  const shared = (rect) => sideways
    ? Math.min(from.y + from.height, rect.y + rect.height) - Math.max(from.y, rect.y)
    : Math.min(from.x + from.width, rect.x + rect.width) - Math.max(from.x, rect.x)

  return Array.from(rects.entries())
    .filter(([ id, rect ]) => id !== desk.focus && ahead(rect) >= 0 && shared(rect) > 0)
    .sort(([ , a ], [ , b ]) => ahead(a) - ahead(b) || shared(b) - shared(a))
    .map(([ id ]) => id)[0] || null
}

/**
 * An arrangement as it is kept, from whatever a browser or the server had: only ever
 * a tool's page in a tile, only tiles a desktop holds and each of them once, desktops
 * one to nine, and those with nothing on them and no name left out. Written the same
 * way every time, so two of them can be compared as text. Nothing when it isn't one.
 * @param {any} kept
 * @returns {State | null}
 */
export function cleaned(kept) {
  if (!kept?.tiles || !kept?.desks) return null

  /** @type {Record<string, Tile>} */
  const known = {}
  for (const [ id, tile ] of Object.entries(kept.tiles)) {
    const url = pathOf(tile?.url)
    if (url && toolIdOf(url)) known[id] = { url, title: String(tile.title || "") }
  }
  /** @type {Record<string, Desk>} */
  const desks = {}
  /** @type {Set<string>} */
  const placedOnce = new Set()
  for (const number of DESKS) {
    const desk = kept.desks[number]
    if (!desk) continue

    const tree = pruned(desk.tree, known, placedOnce)
    const held = leaves(tree)
    const name = deskName(desk.name)
    if (tree || name) desks[number] = { tree, focus: held.includes(desk.focus) ? desk.focus : held[0] || null, alone: Boolean(desk.alone) && Boolean(tree), name }
  }
  /** @type {Record<string, Tile>} */
  const tiles = {}
  for (const id of Array.from(placedOnce).sort()) tiles[id] = known[id]

  return { desk: Math.min(9, Math.max(1, Math.floor(Number(kept.desk)) || 1)), desks, tiles }
}

/**
 * Their arrangement with what was changed here since `base` done again on it: both
 * were made from base. A tile opened here is in it, one closed here is not, one
 * taken to another page here is on that page; a desktop rearranged, named or moved
 * about on here is as it is here, and any other as it is there. Tiles that end up
 * without a place (opened there, on a desktop rearranged here) are for the caller.
 * @param {State} base
 * @param {State} mine
 * @param {State} theirs
 * @returns {State}
 */
export function withChanges(base, mine, theirs) {
  const tiles = { ...theirs.tiles }
  for (const id of Object.keys(base.tiles)) if (!mine.tiles[id]) delete tiles[id]
  for (const [ id, tile ] of Object.entries(mine.tiles)) {
    const was = base.tiles[id]
    if (!was || (tiles[id] && (was.url !== tile.url || was.title !== tile.title))) tiles[id] = tile
  }

  /** @type {(here: unknown, was: unknown) => boolean} */
  const changedHere = (here, was) => JSON.stringify(here) !== JSON.stringify(was)
  /** @type {Record<string, any>} */
  const desks = {}
  for (const number of DESKS) {
    const [ was, here, there ] = [ base, mine, theirs ].map((state) => state.desks[number])
    /** @type {Record<string, unknown>} */
    const desk = {}
    for (const part of /** @type {(keyof Desk)[]} */ ([ "tree", "focus", "alone", "name" ])) desk[part] = (changedHere(here?.[part], was?.[part]) ? here : there)?.[part]
    desks[number] = desk
  }

  return { desk: mine.desk !== base.desk ? mine.desk : theirs.desk, desks, tiles }
}

/**
 * @param {string | null | undefined} text
 * @returns {any}
 */
export function parsed(text) {
  try {
    return text ? JSON.parse(text) : null
  } catch {
    return null
  }
}

/**
 * The desktop an arrangement has a tile on
 * @param {State} state
 * @param {string} id
 * @returns {string | undefined}
 */
export function deskOf(state, id) {
  return Object.keys(state.desks).find((number) => leaves(state.desks[number].tree).includes(id))
}

/**
 * The tiles of a tree, in the order they were split off
 * @param {Tree | null | undefined} node
 * @returns {string[]}
 */
export function leaves(node) {
  if (!node) return []
  return node.tile ? [ node.tile ] : [ ...leaves(node.first), ...leaves(node.second) ]
}

/**
 * @param {Tree | null | undefined} node
 * @param {string} id
 * @returns {Tree | null}
 */
export function find(node, id) {
  if (!node) return null
  return node.tile ? (node.tile === id ? node : null) : find(node.first, id) || find(node.second, id)
}

/**
 * @param {Tree | null | undefined} node
 * @param {string} id
 * @returns {Tree | null}
 */
export function parentOf(node, id) {
  if (!node || node.tile) return null
  if (node.first?.tile === id || node.second?.tile === id) return node
  return parentOf(node.first, id) || parentOf(node.second, id)
}

/**
 * A name as it is kept: without the space around it, and no longer than fits the bar
 * @param {unknown} value
 * @returns {string}
 */
export function deskName(value) {
  return String(value || "").trim().slice(0, DESK_NAME_LENGTH)
}

/**
 * A tile becomes a split, with itself in one half and a new tile in the other
 * @param {Tree | null} node
 * @param {"row" | "column"} split
 * @param {string} tile
 * @param {string} beside
 */
function halve(node, split, tile, beside) {
  if (!node) return

  delete node.tile
  Object.assign(node, { split, ratio: 0.5, first: { tile }, second: { tile: beside } })
}

/**
 * A stored tree with only tiles that still exist, each of them once; a split that
 * lost a half is the other half
 * @param {any} node
 * @param {Record<string, Tile>} tiles
 * @param {Set<string>} seen
 * @returns {Tree | null}
 */
function pruned(node, tiles, seen) {
  if (!node) return null
  if (node.tile) {
    if (!tiles[node.tile] || seen.has(node.tile)) return null
    seen.add(node.tile)
    return { tile: node.tile }
  }

  const first = pruned(node.first, tiles, seen)
  const second = pruned(node.second, tiles, seen)
  if (!first || !second) return first || second

  // To four places: the same number whoever wrote it down
  const ratio = Math.round(Math.min(0.9, Math.max(0.1, Number(node.ratio) || 0.5)) * 10000) / 10000
  return { split: node.split === "column" ? "column" : "row", ratio, first, second }
}

/**
 * @param {Rect | undefined} rect
 * @returns {number}
 */
function area(rect) {
  return rect ? rect.width * rect.height : 0
}

/**
 * How a tile of this size is halved for a new one beside it: along its longer side,
 * or along the other when only that leaves two halves worth having. Nothing when
 * neither does.
 * @param {Rect} rect
 * @returns {"row" | "column" | null}
 */
function splitFor(rect) {
  const row = (rect.width - GAP) / 2 >= ROOM_TO_SPLIT.width && rect.height >= ROOM_TO_SPLIT.height
  const column = (rect.height - GAP) / 2 >= ROOM_TO_SPLIT.height && rect.width >= ROOM_TO_SPLIT.width
  if (row && column) return rect.height > rect.width ? "column" : "row"
  return row ? "row" : column ? "column" : null
}
