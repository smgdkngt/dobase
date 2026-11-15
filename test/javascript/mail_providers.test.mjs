import { test } from "node:test"
import assert from "node:assert/strict"
import { providerOfAddress, providerOfServer } from "services/mail_providers"

const presets = {
  gmail: { domains: [ "gmail.com", "googlemail.com" ], imap_host: "imap.gmail.com" },
  icloud: { domains: [ "icloud.com", "me.com" ], imap_host: "imap.mail.me.com" },
  other: {}
}

test("an address is the service of its domain", () => {
  assert.equal(providerOfAddress("ann@gmail.com", presets), "gmail")
  assert.equal(providerOfAddress("  Ann@Me.com ", presets), "icloud")
})

test("an address of another domain, or half typed, is no service", () => {
  assert.equal(providerOfAddress("ann@example.com", presets), null)
  assert.equal(providerOfAddress("ann", presets), null)
  assert.equal(providerOfAddress("ann@", presets), null)
})

test("servers filled in already are the service they belong to", () => {
  assert.equal(providerOfServer("imap.mail.me.com", presets), "icloud")
  assert.equal(providerOfServer("imap.example.com", presets), null)
  assert.equal(providerOfServer("", presets), null)
})
