import { test } from "node:test"
import assert from "node:assert/strict"
import {
  GAP, NOTHING_OPEN, deskAt, insert, remove, place, neighbour, cleaned, withChanges, parsed, deskOf, leaves, find, parentOf, deskName
} from "services/workspace_layout"

/** @typedef {import("services/workspace_layout").State} State */
/** @typedef {import("services/workspace_layout").Tree} Tree */

// The room a 1400 by 900 window leaves the tiles
const WIDE = { x: GAP, y: 0, width: 1388, height: 900 }
// Too small to halve any tile in
const SMALL = { x: GAP, y: 0, width: 600, height: 400 }

/** @returns {State} */
const nothing = () => structuredClone(NOTHING_OPEN)

/**
 * An arrangement with these trees on its desktops, every tile on a page of its own tool
 * @param {Record<number, Tree>} trees
 * @returns {State}
 */
function arranged(trees) {
  const state = nothing()
  for (const [ number, tree ] of Object.entries(trees)) {
    state.desks[number] = { tree, focus: leaves(tree)[0], alone: false, name: "" }
    for (const id of leaves(tree)) state.tiles[id] = { url: `/tools/${id.charCodeAt(0)}/board`, title: id.toUpperCase() }
  }
  return state
}

/**
 * @param {Tree | string} first
 * @param {Tree | string} second
 * @param {number} [ratio]
 * @returns {Tree}
 */
const row = (first, second, ratio = 0.5) => ({ split: "row", ratio, first: leaf(first), second: leaf(second) })
/**
 * @param {Tree | string} first
 * @param {Tree | string} second
 * @param {number} [ratio]
 * @returns {Tree}
 */
const column = (first, second, ratio = 0.5) => ({ split: "column", ratio, first: leaf(first), second: leaf(second) })
/** @type {(tree: Tree | string) => Tree} */
const leaf = (tree) => typeof tree === "string" ? { tile: tree } : tree

// ── A new tile ──

test("the first tile has the desktop to itself", () => {
  const state = nothing()

  assert.equal(insert(state, WIDE, 1, "a"), 1)
  assert.deepEqual(state.desks[1].tree, { tile: "a" })
})

test("a new tile halves the one you are on: side by side when that is wide", () => {
  const state = arranged({ 1: leaf("a") })

  insert(state, WIDE, 1, "b")

  assert.deepEqual(state.desks[1].tree, row("a", "b"))
})

test("and stacked when it is tall", () => {
  const state = arranged({ 1: row("a", "b") })

  insert(state, WIDE, 1, "c")

  assert.deepEqual(state.desks[1].tree, row(column("a", "c"), "b"))
})

test("when the tile you are on is too small, the biggest one with room is halved", () => {
  const state = arranged({ 1: row("a", "b", 0.3) })

  insert(state, { x: GAP, y: 0, width: 1000, height: 400 }, 1, "c")

  assert.deepEqual(state.desks[1].tree, row("a", row("b", "c"), 0.3))
})

test("when no tile has room, the new one goes to the next desktop with nothing on it", () => {
  const state = arranged({ 1: leaf("a"), 2: leaf("b") })

  assert.equal(insert(state, SMALL, 1, "c"), 3)
  assert.deepEqual(state.desks[1].tree, { tile: "a" })
  assert.deepEqual(state.desks[3].tree, { tile: "c" })
})

test("after the ninth desktop comes the first", () => {
  const state = arranged({ 9: leaf("a") })

  assert.equal(insert(state, SMALL, 9, "b"), 1)
})

test("a desktop that only has a name counts as free", () => {
  const state = arranged({ 1: leaf("a") })
  deskAt(state, 2).name = "Later"

  assert.equal(insert(state, SMALL, 1, "b"), 2)
  assert.equal(state.desks[2].name, "Later")
})

test("with every desktop in use and no room, the tile you are on is halved anyway", () => {
  const state = arranged(Object.fromEntries("abcdefghi".split("").map((id, index) => [ index + 1, leaf(id) ])))

  assert.equal(insert(state, SMALL, 1, "z"), 1)
  assert.deepEqual(state.desks[1].tree, row("a", "z"))
})

// ── A tile gone ──

test("the last tile leaves an empty desktop", () => {
  const state = arranged({ 1: leaf("a") })

  assert.equal(remove(state.desks[1], "a"), undefined)
  assert.equal(state.desks[1].tree, null)
})

test("the other half takes the room of both, and is where you are next", () => {
  const state = arranged({ 1: row("a", column("b", "c")) })

  assert.equal(remove(state.desks[1], "a"), "b")
  assert.deepEqual(state.desks[1].tree, column("b", "c"))
})

test("a tile out of a half leaves the rest of the tree as it was", () => {
  const state = arranged({ 1: row("a", column("b", "c"), 0.3) })

  assert.equal(remove(state.desks[1], "c"), "b")
  assert.deepEqual(state.desks[1].tree, row("a", "b", 0.3))
})

test("a tile the desktop doesn't hold changes nothing", () => {
  const state = arranged({ 1: row("a", "b") })
  state.desks[1].focus = "b"

  assert.equal(remove(state.desks[1], "x"), "b")
  assert.deepEqual(state.desks[1].tree, row("a", "b"))
})

// ── Where tiles are drawn ──

test("tiles fill the room, with a gap between them", () => {
  const state = arranged({ 1: row("a", column("b", "c")) })

  const { tiles, splits } = place(state.desks[1], WIDE)

  assert.deepEqual(tiles.get("a"), { x: 6, y: 0, width: 691, height: 900 })
  assert.deepEqual(tiles.get("b"), { x: 703, y: 0, width: 691, height: 447 })
  assert.deepEqual(tiles.get("c"), { x: 703, y: 453, width: 691, height: 447 })
  assert.deepEqual(splits.map((split) => split.rect), [
    { x: 703, y: 447, width: 691, height: 6 },
    { x: 697, y: 0, width: 6, height: 900 }
  ])
})

test("a split gives its first half the share its ratio says", () => {
  const state = arranged({ 1: row("a", "b", 0.25) })

  const { tiles } = place(state.desks[1], { x: 0, y: 0, width: 1006, height: 500 })

  assert.equal(tiles.get("a")?.width, 250)
  assert.equal(tiles.get("b")?.width, 750)
})

test("an empty desktop has nothing to draw", () => {
  const { tiles, splits } = place(deskAt(nothing(), 1), WIDE)

  assert.equal(tiles.size, 0)
  assert.equal(splits.length, 0)
})

// ── The tile on a side ──

test("the neighbour is the nearest tile on that side", () => {
  const desk = arranged({ 1: row("a", column("b", "c", 0.3)) }).desks[1]

  desk.focus = "c"
  assert.equal(neighbour(desk, WIDE, "left"), "a")
  assert.equal(neighbour(desk, WIDE, "up"), "b")
  assert.equal(neighbour(desk, WIDE, "down"), null)
  assert.equal(neighbour(desk, WIDE, "right"), null)

  desk.focus = "b"
  assert.equal(neighbour(desk, WIDE, "down"), "c")
})

test("of two tiles as near, the one that shares most of the side", () => {
  const desk = arranged({ 1: row("a", column("b", "c", 0.3)) }).desks[1]

  desk.focus = "a"
  assert.equal(neighbour(desk, WIDE, "right"), "c")
})

test("nowhere to go from a desktop without a tile you are on", () => {
  const desk = arranged({ 1: row("a", "b") }).desks[1]
  desk.focus = null

  assert.equal(neighbour(desk, WIDE, "right"), null)
})

// ── What is kept ──

test("an arrangement is kept as it is when nothing is wrong with it", () => {
  const state = arranged({ 1: row("a", "b"), 3: leaf("c") })

  assert.deepEqual(cleaned(state), state)
})

test("what isn't an arrangement is nothing", () => {
  assert.equal(cleaned(null), null)
  assert.equal(cleaned({}), null)
  assert.equal(cleaned({ tiles: {} }), null)
  assert.equal(cleaned("tiles"), null)
})

test("a tile is only ever a page of a tool on this site", () => {
  const state = arranged({ 1: row("a", row("b", row("c", row("d", "e")))) })
  state.tiles.a.url = "https://dobase.test/tools/7/board?card=3"
  state.tiles.b.url = "https://elsewhere.example/tools/7/board"
  state.tiles.c.url = "/profile/edit"
  state.tiles.d.url = "/.//elsewhere.example/tools/7"
  state.tiles.e.url = "javascript:alert(1)"

  const kept = cleaned(state)

  assert.deepEqual(kept?.tiles, { a: { url: "/tools/7/board?card=3", title: "A" } })
  assert.deepEqual(kept?.desks[1].tree, { tile: "a" })
})

test("a tile no desktop holds is dropped, and one held twice is held once", () => {
  const state = arranged({ 1: row("a", "b"), 2: row("a", "c") })
  state.tiles.loose = { url: "/tools/1/chat", title: "Loose" }

  const kept = cleaned(state)

  assert.deepEqual(Object.keys(kept?.tiles || {}), [ "a", "b", "c" ])
  assert.deepEqual(kept?.desks[2].tree, { tile: "c" })
})

test("a ratio stays between a tenth and nine tenths, written to four places", () => {
  /** @type {(ratio: unknown) => number | undefined} */
  const kept = (ratio) => cleaned(arranged({ 1: /** @type {any} */ ({ ...row("a", "b"), ratio }) }))?.desks[1].tree?.ratio

  assert.equal(kept(0.123456), 0.1235)
  assert.equal(kept(0.99), 0.9)
  assert.equal(kept(0), 0.5)
  assert.equal(kept(-3), 0.1)
  assert.equal(kept("wide"), 0.5)
})

test("the tile you are on is one the desktop holds", () => {
  const state = arranged({ 1: row("a", "b") })
  state.desks[1].focus = "gone"

  assert.equal(cleaned(state)?.desks[1].focus, "a")
})

test("a desktop with a name is kept while it is empty, one without is left out", () => {
  const state = arranged({ 1: leaf("a") })
  state.desks[2] = { tree: null, focus: null, alone: true, name: "  Planning  " }
  state.desks[3] = { tree: null, focus: null, alone: false, name: "" }
  state.desks[12] = { tree: { tile: "a" }, focus: "a", alone: false, name: "Twelfth" }

  const kept = cleaned(state)

  assert.deepEqual(Object.keys(kept?.desks || {}), [ "1", "2" ])
  assert.deepEqual(kept?.desks[2], { tree: null, focus: null, alone: false, name: "Planning" })
})

test("the desktop you are on is one of the nine", () => {
  /** @type {(desk: unknown) => number | undefined} */
  const kept = (desk) => cleaned({ ...arranged({ 1: leaf("a") }), desk })?.desk

  assert.equal(kept(4), 4)
  assert.equal(kept("7"), 7)
  assert.equal(kept(0), 1)
  assert.equal(kept(40), 9)
  assert.equal(kept(2.8), 2)
  assert.equal(kept("somewhere"), 1)
})

test("two browsers write the same arrangement the same way", () => {
  const here = arranged({ 1: row("a", "b"), 2: leaf("c") })
  const there = {
    tiles: { c: { title: "C", url: here.tiles.c.url }, b: here.tiles.b, a: here.tiles.a },
    desks: { 2: { name: "", alone: false, focus: "c", tree: { tile: "c" } }, 1: here.desks[1] },
    desk: 1
  }

  assert.equal(JSON.stringify(cleaned(there)), JSON.stringify(cleaned(here)))
})

// ── A change here and a change there ──

test("a tile opened here and one opened there are both open", () => {
  const base = arranged({ 1: leaf("a") })
  const mine = arranged({ 1: row("a", "b") })
  const theirs = arranged({ 1: leaf("a"), 2: leaf("c") })

  const next = withChanges(base, mine, theirs)

  assert.deepEqual(Object.keys(next.tiles).sort(), [ "a", "b", "c" ])
  assert.deepEqual(next.desks[1].tree, row("a", "b"))
  assert.deepEqual(next.desks[2].tree, { tile: "c" })
})

test("a tile closed here stays closed", () => {
  const base = arranged({ 1: row("a", "b") })
  const mine = arranged({ 1: leaf("a") })
  const theirs = arranged({ 1: row("a", "b"), 2: leaf("c") })

  const next = withChanges(base, mine, theirs)

  assert.deepEqual(Object.keys(next.tiles).sort(), [ "a", "c" ])
  assert.deepEqual(next.desks[1].tree, { tile: "a" })
})

test("a tile closed there is not opened again by a browser that only knew of it", () => {
  const base = arranged({ 1: row("a", "b") })
  const mine = structuredClone(base)
  const theirs = arranged({ 1: leaf("a") })

  const next = withChanges(base, mine, theirs)

  assert.deepEqual(Object.keys(next.tiles), [ "a" ])
  assert.deepEqual(next.desks[1].tree, { tile: "a" })
})

test("a tile taken to another page here is on that page", () => {
  const base = arranged({ 1: leaf("a") })
  const mine = structuredClone(base)
  mine.tiles.a.url = "/tools/97/board?card=3"
  const theirs = structuredClone(base)

  assert.equal(withChanges(base, mine, theirs).tiles.a.url, "/tools/97/board?card=3")
})

test("a desktop changed here is as it is here, any other as it is there", () => {
  const base = arranged({ 1: row("a", "b"), 2: leaf("c") })
  const mine = structuredClone(base)
  mine.desks[1].tree = row("b", "a")
  mine.desks[1].name = "Mine"
  const theirs = structuredClone(base)
  theirs.desks[1].name = "Theirs"
  theirs.desks[2].name = "Second"
  theirs.desk = 2

  const next = withChanges(base, mine, theirs)

  assert.deepEqual(next.desks[1].tree, row("b", "a"))
  assert.equal(next.desks[1].name, "Mine")
  assert.equal(next.desks[2].name, "Second")
  assert.equal(next.desk, 2)
})

test("the desktop gone to here is where you are", () => {
  const base = arranged({ 1: leaf("a"), 2: leaf("b") })
  const mine = { ...structuredClone(base), desk: 2 }
  const theirs = structuredClone(base)

  assert.equal(withChanges(base, mine, theirs).desk, 2)
})

test("a tile opened there on a desktop rearranged here has no place yet", () => {
  const base = arranged({ 1: row("a", "b") })
  const mine = arranged({ 1: row("b", "a") })
  const theirs = arranged({ 1: row("a", row("b", "c")) })

  const next = withChanges(base, mine, theirs)
  const kept = cleaned(next)

  assert.ok(next.tiles.c)
  assert.deepEqual(next.desks[1].tree, row("b", "a"))
  assert.equal(kept?.tiles.c, undefined)
})

// ── Looking things up ──

test("the tiles of a tree, in the order they were split off", () => {
  assert.deepEqual(leaves(row("a", column("b", row("c", "d")))), [ "a", "b", "c", "d" ])
  assert.deepEqual(leaves(null), [])
})

test("a tile in a tree, and the split it is a half of", () => {
  const tree = row("a", column("b", "c"))

  assert.deepEqual(find(tree, "c"), { tile: "c" })
  assert.equal(find(tree, "x"), null)
  assert.equal(parentOf(tree, "c"), tree.second)
  assert.equal(parentOf(tree, "a"), tree)
  assert.equal(parentOf(leaf("a"), "a"), null)
})

test("the desktop a tile is on", () => {
  const state = arranged({ 1: leaf("a"), 4: row("b", "c") })

  assert.equal(deskOf(state, "c"), "4")
  assert.equal(deskOf(state, "x"), undefined)
})

test("a desktop's name has no space around it and fits the bar", () => {
  assert.equal(deskName("  Planning "), "Planning")
  assert.equal(deskName(null), "")
  assert.equal(deskName("a".repeat(40)).length, 24)
})

test("text that isn't an arrangement reads as nothing", () => {
  assert.deepEqual(parsed('{"desk":1}'), { desk: 1 })
  assert.equal(parsed("{"), null)
  assert.equal(parsed(""), null)
  assert.equal(parsed(null), null)
})
