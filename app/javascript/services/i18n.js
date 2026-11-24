// The words a script shows, in the page's language (Translation on the server).
//
// A text is written in English where it is used and handed to `_`, as in the views:
//
//   _("Saved %{time}", { time })
//
// The page's <head> carries the Persian of every text the scripts have (config/locales/
// fa/js.yml) in <meta name="translations">; English pages carry none, and a text without
// a translation stays English. Changing the language reloads the page, so this is read once.

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

/** The page's language: "en" or "fa" */
export function locale() {
  return (typeof document === "undefined" ? "" : document.documentElement.lang) || "en"
}

/** Whether the page reads right to left */
export function rtl() {
  return typeof document !== "undefined" && document.documentElement.dir === "rtl"
}

/**
 * The language's name for dates and numbers, for Intl: Persian is written with its own
 * digits and its own (solar) calendar
 * @returns {string}
 */
export function intlLocale() {
  return locale() === "fa" ? "fa-IR" : "en-US"
}

/**
 * 0-9 as the language writes them
 * @param {string | number} text
 * @returns {string}
 */
export function digits(text) {
  const value = String(text)
  return locale() === "fa" ? value.replace(/[0-9]/g, (digit) => "۰۱۲۳۴۵۶۷۸۹"[Number(digit)]) : value
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
