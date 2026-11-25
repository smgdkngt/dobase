import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { _, n_, digits, intlLocale, forgetTranslations } from "services/i18n"

/**
 * A page in this language, carrying these translations
 * @param {string} lang
 * @param {Record<string, string> | null} translations
 */
function page(lang, translations) {
  globalThis.document = /** @type {any} */ ({
    documentElement: { lang, dir: lang === "fa" ? "rtl" : "ltr" },
    querySelector: () => (translations ? { getAttribute: () => JSON.stringify(translations) } : null)
  })
  forgetTranslations()
}

beforeEach(() => page("en", null))

test("an English page shows the text as it is written, filled in", () => {
  assert.equal(_("Saved %{time}", { time: "12:04" }), "Saved 12:04")
  assert.equal(n_("%{count} file", "%{count} files", 1), "1 file")
  assert.equal(n_("%{count} file", "%{count} files", 3), "3 files")
})

test("a Persian page shows the translation, with Persian digits in numbers", () => {
  page("fa", { "Saved %{time}": "ذخیره شد %{time}", "%{count} files": "%{count} پرونده" })
  assert.equal(_("Saved %{time}", { time: "۱۲:۰۴" }), "ذخیره شد ۱۲:۰۴")
  assert.equal(n_("%{count} file", "%{count} files", 3), "۳ پرونده")
  assert.equal(digits("2026"), "۲۰۲۶")
})

test("Intl knows a language by the name the table gives it, else by its own", () => {
  assert.equal(intlLocale(), "en-US")
  page("fa", {})
  assert.equal(intlLocale(), "fa-IR")
  page("nl", {})
  assert.equal(intlLocale(), "nl")
  assert.equal(digits("2026"), "2026")
})

test("a text without a translation stays English", () => {
  page("fa", {})
  assert.equal(_("Undo"), "Undo")
})
