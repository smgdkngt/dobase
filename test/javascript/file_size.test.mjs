import { test } from "node:test"
import assert from "node:assert/strict"
import { formatFileSize } from "services/file_size"

// The same sizes test/helpers/formatting_helper_test.rb asks of the server
test("a size reads the way the server writes it", () => {
  assert.equal(formatFileSize(0), "0 B")
  assert.equal(formatFileSize(397), "397 B")
  assert.equal(formatFileSize(1024), "1 KB")
  assert.equal(formatFileSize(8704), "8.5 KB")
  assert.equal(formatFileSize(25 * 1024 * 1024), "25 MB")
  assert.equal(formatFileSize(3.26 * 1024 ** 3), "3.3 GB")
  assert.equal(formatFileSize(5000 * 1024 ** 4), "5000 TB")
})

test("what isn't a size is nothing", () => {
  assert.equal(formatFileSize(null), "0 B")
  assert.equal(formatFileSize("many"), "0 B")
  assert.equal(formatFileSize(-12), "0 B")
  assert.equal(formatFileSize("2048"), "2 KB")
})
