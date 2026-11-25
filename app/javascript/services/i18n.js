/** @type {Record<string, string | Record<string, string>> | null} */
let table = null

/** @returns {Record<string, string | Record<string, string>>} */
function translations() {
  if (table) return table
  const meta = typeof document === "undefined" ? null : document.querySelector('meta[name="translations"]')
  try {
    table = meta ? JSON.parse(meta.getAttribute("content") || "{}") : {}
  } catch {
    table = {}
  }
  return /** @type {Record<string, string | Record<string, string>>} */ (table)
}

/** @type {Record<string, string>} */
const INTL_LOCALES = {
  en: "en-US",
  pt: "pt-BR",
  fa: "fa-IR",
  ar: "ar-u-nu-latn",
  he: "he-IL",
  nb: "nb-NO",
  zh: "zh-CN",
  hi: "hi-IN"
}

export function locale() {
  return (typeof document === "undefined" ? "" : document.documentElement.lang) || "en"
}

export function rtl() {
  return typeof document !== "undefined" && document.documentElement.dir === "rtl"
}

/** @returns {string} */
export function intlLocale() {
  return INTL_LOCALES[locale()] || locale()
}

/**
 * @param {string | number} text
 * @returns {string}
 */
export function digits(text) {
  const number = new Intl.NumberFormat(intlLocale(), { useGrouping: false })
  return String(text).replace(/[0-9]/g, (digit) => number.format(Number(digit)))
}

/** @param {Element | DocumentFragment} root */
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
 * @param {string} template
 * @param {Record<string, string | number>} values
 * @returns {string}
 */
function interpolate(template, values) {
  return template.replace(/%\{(\w+)\}/g, (whole, name) => {
    if (!(name in values)) return whole
    const value = values[name]
    return typeof value === "number" ? digits(value) : String(value)
  })
}

/**
 * @param {string} other
 * @param {number} count
 * @returns {string | undefined}
 */
function pluralTemplate(other, count) {
  const entry = translations()[other]
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    const category = new Intl.PluralRules(intlLocale()).select(count)
    return entry[category] ?? entry.other
  }
  return undefined
}

/**
 * @param {string} text
 * @param {Record<string, string | number>} [values]
 * @returns {string}
 */
export function _(text, values = {}) {
  const entry = translations()[text]
  return interpolate(typeof entry === "string" ? entry : text, values)
}

/**
 * @param {string} one
 * @param {string} other
 * @param {number} count
 * @param {Record<string, string | number>} [values]
 * @returns {string}
 */
export function n_(one, other, count, values = {}) {
  const template = pluralTemplate(other, count) ?? (count === 1 ? one : other)
  return interpolate(template, { ...values, count })
}

export function forgetTranslations() {
  table = null
}
