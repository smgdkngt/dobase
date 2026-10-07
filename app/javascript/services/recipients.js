// The people in a To, Cc or Bcc field as text: what is typed or pasted into one, and
// what the form sends ("Ann Lee <ann@example.com>, joe@example.com").

/**
 * @typedef {{ name: string, address: string }} Recipient
 */

// A piece between commas, semicolons or lines; a quoted name may have those in it
const PIECE = /(?:"(?:[^"\\]|\\.)*"|<[^>]*>|[^,;\n])+/g
const ADDRESS = /^[^\s@<>,;:"()]+@[^\s@<>,;:"()]+\.[^\s@<>,;:"().]+$/
// What a name can't have outside quotes in a mail's header
const SPECIAL = /[,;:<>@"()[\]\\.]/

/**
 * @param {string} address
 * @returns {boolean}
 */
export function validAddress(address) {
  return ADDRESS.test(address)
}

/**
 * Everyone in a piece of text: "Ann Lee <ann@example.com>; joe@example.com". Addresses
 * with only spaces between them are taken apart too. What is no address stays as it
 * was written, for the field to say so.
 *
 * @param {string} text
 * @returns {Recipient[]}
 */
export function parseRecipients(text) {
  return (text.match(PIECE) || []).flatMap((piece) => {
    piece = piece.trim().replace(/^mailto:/i, "")
    if (!piece) return []

    const named = piece.match(/^(.*?)\s*<\s*([^<>]*?)\s*>$/)
    if (named) return [{ name: unquoted(named[1]), address: named[2] }]

    const words = piece.split(/\s+/)
    if (words.length > 1 && words.every(validAddress)) return words.map((address) => ({ name: "", address }))

    return [{ name: "", address: piece }]
  })
}

/**
 * @param {Recipient} recipient
 * @returns {string}
 */
export function formatRecipient({ name, address }) {
  if (!name || !validAddress(address)) return address

  const written = SPECIAL.test(name) ? `"${name.replace(/(["\\])/g, "\\$1")}"` : name
  return `${written} <${address}>`
}

/**
 * Whether text put into a field is a list of people, not a part of one still being typed.
 *
 * @param {string} text
 * @returns {boolean}
 */
export function listOfRecipients(text) {
  const found = parseRecipients(text)
  return found.length > 1 || (found.length === 1 && validAddress(found[0].address))
}

/**
 * Whether a comma or semicolon typed after this text is inside a quoted name.
 *
 * @param {string} text
 * @returns {boolean}
 */
export function inQuotes(text) {
  return (text.replace(/\\./g, "").match(/"/g) || []).length % 2 === 1
}

/**
 * @param {string} name
 * @returns {string}
 */
function unquoted(name) {
  name = name.trim()
  return /^".*"$/.test(name) ? name.slice(1, -1).replace(/\\(.)/g, "$1") : name
}
