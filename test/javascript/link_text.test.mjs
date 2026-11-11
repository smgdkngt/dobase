import { test } from "node:test"
import assert from "node:assert/strict"
import { addressAtStart, hrefFor, madeByItsText } from "services/link_text"

const FEED = "https://bo.example.com/feeds/feed-3ff8.csv"

test("an address goes on to the first space, querystring and all", () => {
  assert.equal(addressAtStart(`${FEED}?token=AbC123 done`), `${FEED}?token=AbC123`)
  assert.equal(addressAtStart(`${FEED}?token=AbC123&format=csv`), `${FEED}?token=AbC123&format=csv`)
  assert.equal(addressAtStart(`${FEED}?token=`), `${FEED}?token=`)
  assert.equal(addressAtStart(`${FEED}?token=AbC123<br>`), `${FEED}?token=AbC123`)
})

// The same trimming as Mcp::Text and the CLI's linkURLs
test("punctuation that ends a sentence, or a bracket it didn't open, isn't part of it", () => {
  assert.equal(addressAtStart(`${FEED}?token=AbC123.`), `${FEED}?token=AbC123`)
  assert.equal(addressAtStart("https://example.com/a?b=1, and"), "https://example.com/a?b=1")
  assert.equal(addressAtStart("https://example.com)."), "https://example.com")
  assert.equal(addressAtStart("https://en.wikipedia.org/wiki/Rails_(software)"), "https://en.wikipedia.org/wiki/Rails_(software)")
})

test("a link its text made follows that text; a link on words of its own doesn't", () => {
  assert.ok(madeByItsText(FEED, FEED))
  assert.ok(madeByItsText(`${FEED}?token=AbC123`, FEED), "an address that grew")
  assert.ok(madeByItsText(`${FEED}?token=AbC123 done`, `${FEED}?token=`), "and a word after it")
  assert.ok(madeByItsText("www.example.com/a", "http://www.example.com/a"))
  assert.ok(!madeByItsText("the feed", FEED))
  assert.ok(!madeByItsText("https://example.com", "https://other.example.org"))
})

test("an address without a scheme goes to http", () => {
  assert.equal(hrefFor("www.example.com"), "http://www.example.com")
  assert.equal(hrefFor(FEED), FEED)
})
