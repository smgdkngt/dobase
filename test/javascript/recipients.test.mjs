import { test } from "node:test"
import assert from "node:assert/strict"
import { formatRecipient, inQuotes, listOfRecipients, parseRecipients, validAddress } from "services/recipients"

test("a pasted list becomes one recipient per address", () => {
  assert.deepEqual(parseRecipients("Ann Lee <ann@example.com>, joe@example.com; kim@example.com\nlou@example.com"), [
    { name: "Ann Lee", address: "ann@example.com" },
    { name: "", address: "joe@example.com" },
    { name: "", address: "kim@example.com" },
    { name: "", address: "lou@example.com" }
  ])
})

test("a quoted name keeps its comma", () => {
  assert.deepEqual(parseRecipients('"Lee, Ann" <ann@example.com>, joe@example.com'), [
    { name: "Lee, Ann", address: "ann@example.com" },
    { name: "", address: "joe@example.com" }
  ])
})

test("addresses with only spaces between them are taken apart", () => {
  assert.deepEqual(parseRecipients("ann@example.com joe@example.com").map((one) => one.address), [ "ann@example.com", "joe@example.com" ])
})

test("a link to write to someone is their address", () => {
  assert.deepEqual(parseRecipients("mailto:ann@example.com"), [ { name: "", address: "ann@example.com" } ])
  assert.deepEqual(parseRecipients("<ann@example.com>"), [ { name: "", address: "ann@example.com" } ])
})

test("what is no address stays as it was written", () => {
  assert.deepEqual(parseRecipients("Ann Lee"), [ { name: "", address: "Ann Lee" } ])
  assert.deepEqual(parseRecipients(" , ;"), [])
})

test("an address has a name, an @ and a domain with a dot", () => {
  assert.ok(validAddress("ann.lee+news@mail.example.com"))
  for (const wrong of [ "ann", "ann@", "ann@example", "ann lee@example.com", "ann@example.", "@example.com" ]) {
    assert.ok(!validAddress(wrong), wrong)
  }
})

test("a recipient is written the way a mail's header has it", () => {
  assert.equal(formatRecipient({ name: "Ann Lee", address: "ann@example.com" }), "Ann Lee <ann@example.com>")
  assert.equal(formatRecipient({ name: "", address: "ann@example.com" }), "ann@example.com")
  assert.equal(formatRecipient({ name: 'Lee, Ann "AL"', address: "ann@example.com" }), '"Lee, Ann \\"AL\\"" <ann@example.com>')
  assert.equal(formatRecipient({ name: "Ann", address: "not an address" }), "not an address")
})

test("what is written comes back the same when it is read again", () => {
  const people = [ { name: 'Lee, Ann "AL"', address: "ann@example.com" }, { name: "Zoë Ex", address: "zoe@example.com" } ]
  assert.deepEqual(parseRecipients(people.map(formatRecipient).join(", ")), people)
})

test("a paste is a list when it holds an address, not when it is a part of one", () => {
  assert.ok(listOfRecipients("ann@example.com"))
  assert.ok(listOfRecipients("Ann <ann@example.com>"))
  assert.ok(listOfRecipients("ann, joe"))
  assert.ok(!listOfRecipients("example.com"))
  assert.ok(!listOfRecipients("Ann Lee"))
})

test("a comma inside an open quote belongs to the name", () => {
  assert.ok(inQuotes('"Lee'))
  assert.ok(!inQuotes('"Lee, Ann"'))
  assert.ok(!inQuotes("Lee"))
})
