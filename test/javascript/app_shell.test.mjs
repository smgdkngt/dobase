import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { Script } from "node:vm"

// The app `dobase app install` makes is Electron started on these scripts, which
// are of the older kind there (require, module.exports) and so are read as that
const shell = new URL("../../cli/internal/command/shell/", import.meta.url)
const script = (/** @type {string} */ name) => new Script(`(function (require, module, exports, __dirname) {${readFileSync(new URL(name, shell), "utf8")}\n})`, { filename: name })
const links = { exports: /** @type {Record<string, (...given: any[]) => any>} */ ({}) }
script("links.js").runInThisContext()(null, links, links.exports, "")
const { inside, page, outward } = links.exports

test("the server's own pages are inside, everything else is not", () => {
  for (const address of ["https://dobase.test/", "https://dobase.test/tools/8/board?card=3#top", "https://dobase.test"]) {
    assert.ok(inside("https://dobase.test", address), address)
    assert.ok(inside("https://dobase.test/", address), address)
  }
  for (const address of ["http://dobase.test/", "https://dobase.test.example.com/", "https://dobase.test:8443/", "https://example.com/https://dobase.test/",
    "https://dobase.test@example.com/", "blob:https://dobase.test/1234", "javascript:alert(1)", "about:blank", "", "tools/8", null, undefined]) {
    assert.ok(!inside("https://dobase.test", address), String(address))
  }
})

test("a server under a path keeps to that path", () => {
  assert.ok(inside("https://example.com/dobase", "https://example.com/dobase/tools/8"))
  assert.ok(inside("https://example.com/dobase/", "https://example.com/dobase"))
  assert.ok(!inside("https://example.com/dobase", "https://example.com/"))
  assert.ok(!inside("https://example.com/dobase", "https://example.com/dobase-two/tools/8"))
})

test("a link handed to the app is a page of the server or nothing", () => {
  assert.equal(page("https://dobase.test", "web+dobase://tools/8/mails/new?draft_id=400"), "https://dobase.test/tools/8/mails/new?draft_id=400")
  assert.equal(page("https://dobase.test/", "web+dobase:tools/8"), "https://dobase.test/tools/8")
  assert.equal(page("https://dobase.test", "web+dobase://"), "https://dobase.test/")
  assert.equal(page("https://example.com/dobase", "web+dobase://tools/8"), "https://example.com/dobase/tools/8")
  assert.equal(page("https://dobase.test", "https://dobase.test/tools/8"), "https://dobase.test/tools/8")

  // What Electron is started with beside a link, and links that lead away
  for (const link of ["https://example.com/tools/8", "web+dobase://../../etc", "/home/someone/.local/share/dobase/shell", "--no-sandbox", "", null, undefined]) {
    const address = page("https://example.com/dobase", link)
    assert.ok(address === null || address.startsWith("https://example.com/dobase/"), `${link} became ${address}`)
  }
  assert.equal(page("https://dobase.test", "https://example.com/"), null)
  assert.equal(page("https://dobase.test", "/home/someone/.local/share/dobase/shell"), null)
  assert.equal(page("https://dobase.test", undefined), null)
})

test("only pages, letters and numbers to call are handed to the system", () => {
  for (const address of ["https://example.com/", "http://example.com/", "mailto:someone@example.com", "tel:+31612345678"]) assert.ok(outward(address), address)
  for (const address of ["file:///etc/passwd", "javascript:alert(1)", "smb://server/share", "vscode://open", "", "example.com", null]) assert.ok(!outward(address), String(address))
})

test("the scripts are ones Electron can read", () => {
  for (const name of ["main.js", "preload.js", "links.js"]) assert.doesNotThrow(() => script(name), name)
})
