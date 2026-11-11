// What part of a run of text is a web address, the way the server and the CLI
// read it (Mcp::Text, `command.Paragraphs`): up to the first space or "<",
// without punctuation that ends a sentence or a bracket closed that wasn't opened.
// A querystring goes along whole: "?token=abc&x=1" is part of the address.

const TRAILING = ".,;:!?'\"*_"

/**
 * Whether a link's text is itself an address, as one typed or pasted is.
 * @param {string} text
 * @returns {boolean}
 */
export function looksLikeAddress(text) {
  return /^(https?:\/\/|mailto:|www\.)\S/i.test(text)
}

/**
 * The address a link with this text goes to.
 * @param {string} text
 * @returns {string}
 */
export function hrefFor(text) {
  return /^www\./i.test(text) ? `http://${text}` : text
}

/**
 * The address at the start of text: up to a space or "<", trimmed.
 * @param {string} text
 * @returns {string}
 */
export function addressAtStart(text) {
  let address = text.split(/[\s<￼]/, 1)[0]
  while (address) {
    const last = address[address.length - 1]
    if (TRAILING.includes(last)) {
      address = address.slice(0, -1)
    } else if (last === ")" && count(address, "(") < count(address, ")")) {
      address = address.slice(0, -1)
    } else if (last === "]" && count(address, "[") < count(address, "]")) {
      address = address.slice(0, -1)
    } else {
      break
    }
  }
  return address
}

/**
 * Whether a link is one that its text made (typed, pasted, linked by the editor):
 * its address is its text, or was, before the text was added to or cut short.
 * A link put on words of its own (Cmd+K on "the feed") isn't.
 * @param {string} text
 * @param {string} href
 * @returns {boolean}
 */
export function madeByItsText(text, href) {
  if (!looksLikeAddress(text)) return false
  const address = hrefFor(addressAtStart(text))
  return href === address || address.startsWith(href) || href.startsWith(address)
}

/**
 * @param {string} text
 * @param {string} character
 * @returns {number}
 */
function count(text, character) {
  return text.split(character).length - 1
}
