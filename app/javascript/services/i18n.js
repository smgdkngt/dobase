// The words a script shows, in the page's language (Translation on the server).
//
// A text is written in English where it is used and handed to `_`, as in the views:
//
//   _("Saved %{time}", { time })
//
// The page's <head> carries the translation of every text the scripts have (config/locales/
// <language>/js.yml) in <meta name="translations">; English pages carry none, and a text
// without a translation stays English. Changing the language reloads the page, so this is
// read once.

/** @type {Record<string, string> | null} */
let table = null

/** @returns {Record<string, string>} */
function translations() {
  if (table) return table
  const meta = typeof document === "undefined" ? null : document.querySelector('meta[name="translations"]')
  try {
    table = meta ? JSON.parse(meta.getAttribute("content") || "{}") : {}
  } catch {
    table = {}
  }
  return /** @type {Record<string, string>} */ (table)
}

// The name Intl knows a language by, where the page's own isn't the one meant: English
// as the server writes it (12-hour clock, the month first), Persian as in Iran (its
// digits and solar calendar). Any other language is Intl's by its own name.
/** @type {Record<string, string>} */
const INTL_LOCALES = { en: "en-US", fa: "fa-IR" }

/** The page's language, as Translation::LANGUAGES names it */
export function locale() {
  return (typeof document === "undefined" ? "" : document.documentElement.lang) || "en"
}

/** Whether the page reads right to left */
export function rtl() {
  return typeof document !== "undefined" && document.documentElement.dir === "rtl"
}

/**
 * The language's name for dates and numbers, for Intl
 * @returns {string}
 */
export function intlLocale() {
  return INTL_LOCALES[locale()] || locale()
}

/**
 * 0-9 as the language writes them
 * @param {string | number} text
 * @returns {string}
 */
export function digits(text) {
  const number = new Intl.NumberFormat(intlLocale(), { useGrouping: false })
  return String(text).replace(/[0-9]/g, (digit) => number.format(Number(digit)))
}

/**
 * Writes the texts a part of the page names in `data-words` in the page's language
 * (ApplicationHelper#words): a part broadcast to everyone, like a chat message, is drawn
 * once in English. Each attribute named is set, `text` is the element's own text, and a
 * list of values is joined as the language joins one.
 * @param {Element | DocumentFragment} root
 */
export function translateWords(root) {
  const marked = [ ...("matches" in root && root.matches("[data-words]") ? [ root ] : []), ...root.querySelectorAll("[data-words]") ]
  for (const element of marked) {
    /** @type {Record<string, [string, Record<string, string | number | string[]>?]>} */
    let texts
    try {
      texts = JSON.parse(element.getAttribute("data-words") || "{}")
    } catch {
      continue
    }
    for (const [attribute, [text, values = {}]] of Object.entries(texts)) {
      const written = _(text, listsJoined(values))
      if (attribute === "text") element.textContent = written
      else element.setAttribute(attribute, written)
    }
  }
  root.querySelectorAll("template").forEach((template) => translateWords(template.content))
}

/**
 * @param {Record<string, string | number | string[]>} values
 * @returns {Record<string, string | number>}
 */
function listsJoined(values) {
  const list = new Intl.ListFormat(intlLocale(), { type: "conjunction" })
  return Object.fromEntries(Object.entries(values).map(([name, value]) => [ name, Array.isArray(value) ? list.format(value) : value ]))
}

/**
 * The text in the page's language, with %{name} filled in
 * @param {string} text
 * @param {Record<string, string | number>} [values]
 * @returns {string}
 */
export function _(text, values = {}) {
  const template = translations()[text] ?? text
  return template.replace(/%\{(\w+)\}/g, (whole, name) => {
    if (!(name in values)) return whole
    const value = values[name]
    return typeof value === "number" ? digits(value) : String(value)
  })
}

/**
 * One text or the other by the count, with %{count} filled in
 * @param {string} one
 * @param {string} other
 * @param {number} count
 * @param {Record<string, string | number>} [values]
 * @returns {string}
 */
export function n_(one, other, count, values = {}) {
  const translated = translations()[other]
  return _(translated ?? (count === 1 ? one : other), { ...values, count })
}

/** For tests: forget the table read from the page */
export function forgetTranslations() {
  table = null
}
