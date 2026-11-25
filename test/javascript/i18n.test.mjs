import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { _, n_, digits, intlLocale, forgetTranslations } from "services/i18n"

/**
 * @param {string} lang
 * @param {Record<string, string | Record<string, string>> | null} translations
 */
function page(lang, translations) {
  globalThis.document = /** @type {any} */ ({
    documentElement: { lang, dir: [ "fa", "ar", "he" ].includes(lang) ? "rtl" : "ltr" },
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
  page("ar", {})
  assert.equal(intlLocale(), "ar-u-nu-latn")
  assert.equal(digits("2026"), "2026")
  page("he", {})
  assert.equal(intlLocale(), "he-IL")
  page("nb", {})
  assert.equal(intlLocale(), "nb-NO")
  page("zh", {})
  assert.equal(intlLocale(), "zh-CN")
  page("hi", {})
  assert.equal(intlLocale(), "hi-IN")
  page("nl", {})
  assert.equal(intlLocale(), "nl")
  assert.equal(digits("2026"), "2026")
})

test("a text without a translation stays English", () => {
  page("fa", {})
  assert.equal(_("Undo"), "Undo")
})

test("plural hashes follow the language's CLDR rules and fall back to other", () => {
  page("ar", {
    "%{count} files": {
      zero: "لا توجد ملفات",
      one: "ملف واحد",
      two: "ملفان",
      few: "%{count} ملفات",
      many: "%{count} ملفاً",
      other: "%{count} ملف"
    },
    "%{count} cards": {
      one: "بطاقة واحدة",
      other: "%{count} بطاقة"
    }
  })
  assert.equal(n_("%{count} file", "%{count} files", 0), "لا توجد ملفات")
  assert.equal(n_("%{count} file", "%{count} files", 1), "ملف واحد")
  assert.equal(n_("%{count} file", "%{count} files", 2), "ملفان")
  assert.equal(n_("%{count} file", "%{count} files", 5), "5 ملفات")
  assert.equal(n_("%{count} file", "%{count} files", 15), "15 ملفاً")
  assert.equal(n_("%{count} file", "%{count} files", 100), "100 ملف")
  assert.equal(n_("%{count} card", "%{count} cards", 0), "0 بطاقة")
  assert.equal(n_("%{count} card", "%{count} cards", 1), "بطاقة واحدة")
  assert.equal(n_("%{count} card", "%{count} cards", 5), "5 بطاقة")

  page("pl", {
    "%{count} files": {
      one: "%{count} plik",
      few: "%{count} pliki",
      many: "%{count} plików",
      other: "%{count} pliku"
    },
    "%{count} cards": {
      one: "%{count} karta",
      few: "%{count} karty",
      other: "%{count} kart"
    }
  })
  assert.equal(n_("%{count} file", "%{count} files", 1), "1 plik")
  assert.equal(n_("%{count} file", "%{count} files", 3), "3 pliki")
  assert.equal(n_("%{count} file", "%{count} files", 5), "5 plików")
  assert.equal(n_("%{count} file", "%{count} files", 1.5), "1.5 pliku")
  assert.equal(n_("%{count} card", "%{count} cards", 5), "5 kart")

  page("fr", {
    "%{count} files": {
      one: "%{count} fichier",
      other: "%{count} fichiers"
    }
  })
  assert.equal(n_("%{count} file", "%{count} files", 0), "0 fichier")
  assert.equal(n_("%{count} file", "%{count} files", 1), "1 fichier")
  assert.equal(n_("%{count} file", "%{count} files", 2), "2 fichiers")

  page("he", {
    "%{count} files": {
      one: "קובץ אחד",
      two: "שני קבצים",
      other: "%{count} קבצים"
    }
  })
  assert.equal(n_("%{count} file", "%{count} files", 1), "קובץ אחד")
  assert.equal(n_("%{count} file", "%{count} files", 2), "שני קבצים")
  assert.equal(n_("%{count} file", "%{count} files", 3), "3 קבצים")

  page("ja", {
    "%{count} files": {
      other: "%{count}件のファイル"
    }
  })
  assert.equal(n_("%{count} file", "%{count} files", 1), "1件のファイル")
  assert.equal(n_("%{count} file", "%{count} files", 5), "5件のファイル")
})
