# frozen_string_literal: true

require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  STRING = /"((?:[^"\\]|\\.)*)"/
  ONE = /(?:(?<![\w.])_|Translation\.translate)\(\s*#{STRING}/
  TWO = /(?:(?<![\w.])n_|Translation\.translate_plural)\(\s*#{STRING}\s*,\s*#{STRING}/
  LANGUAGES = Translation.locales - [ "en" ]

  PLURAL_CATEGORIES = {
    "en" => %i[one other],
    "nl" => %i[one other],
    "de" => %i[one other],
    "fr" => %i[one many other],
    "es" => %i[one many other],
    "pt" => %i[one many other],
    "it" => %i[one many other],
    "fa" => %i[one other],
    "ar" => %i[zero one two few many other],
    "he" => %i[one two other],
    "tr" => %i[one other],
    "pl" => %i[one few many other],
    "uk" => %i[one few many other],
    "cs" => %i[one few many other],
    "ro" => %i[one few other],
    "sv" => %i[one other],
    "da" => %i[one other],
    "nb" => %i[one other],
    "fi" => %i[one other],
    "ja" => %i[other],
    "ko" => %i[other],
    "zh" => %i[other],
    "id" => %i[other],
    "hi" => %i[one other]
  }.freeze

  teardown { I18n.locale = :en }

  test "every text in the code has its translation in every language" do
    texts, plurals = texts_in(Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,builder}")].reject { |path| path.include?("app/javascript") })

    LANGUAGES.each do |locale|
      untranslated = texts.reject { |text| translated?(locale, :ui, text) } + plurals.map(&:last).reject { |other| plural_translated?(locale, :ui, other) }
      assert_empty untranslated.uniq, "Add these to config/locales/#{locale}/ui.yml"
    end
  end

  test "every kind of tool has its name and description in every language" do
    texts = File.read(Rails.root.join("db/seeds.rb")).scan(/\{ name: #{STRING}, slug: .*description: #{STRING} \}/).flatten

    assert_equal 16, texts.size
    LANGUAGES.each do |locale|
      assert_empty texts.reject { |text| translated?(locale, :ui, text) }, "Add these to config/locales/#{locale}/ui.yml"
    end
  end

  test "every text a script shows has its translation in every language" do
    texts, plurals = texts_in(Dir[Rails.root.join("app/javascript/**/*.js")])
    texts += words_in(Dir[Rails.root.join("app/views/**/*.erb")])

    LANGUAGES.each do |locale|
      untranslated = texts.reject { |text| translated?(locale, :js, text) } + plurals.map(&:last).reject { |other| plural_translated?(locale, :js, other) }
      assert_empty untranslated.uniq, "Add these to config/locales/#{locale}/js.yml"
    end
  end

  test "a translation fills in the same values as its English" do
    LANGUAGES.each do |locale|
      %i[ui js].each do |scope|
        I18n.t(scope, locale: locale).each do |english, translated|
          expected = english.to_s.scan(/%\{\w+\}/).sort
          if translated.is_a?(Hash)
            translated.each do |category, form|
              actual = form.to_s.scan(/%\{\w+\}/).sort
              if %i[zero one two].include?(category)
                required = expected - [ "%{count}" ]
                assert_empty actual - expected, "#{locale} #{scope}: #{english} (#{category})"
                assert_empty required - actual, "#{locale} #{scope}: #{english} (#{category})"
              else
                assert_equal expected, actual, "#{locale} #{scope}: #{english} (#{category})"
              end
            end
          else
            assert_equal expected, translated.scan(/%\{\w+\}/).sort, "#{locale} #{scope}: #{english}"
          end
        end
      end
    end
  end

  test "plural entries have other and only categories that language has" do
    LANGUAGES.each do |locale|
      %i[ui js].each do |scope|
        I18n.t(scope, locale: locale).each do |english, entry|
          next unless entry.is_a?(Hash)

          assert_empty plural_entry_errors(locale, entry), "#{locale} #{scope}: #{english}"
        end
      end
    end

    assert_empty plural_entry_errors("ar", { zero: "0", one: "1", two: "2", few: "3", many: "11", other: "100" })
    assert_empty plural_entry_errors("ar", { one: "1", other: "n" })
    assert_empty plural_entry_errors("ja", { other: "n" })
    assert_empty plural_entry_errors("pl", { one: "1", few: "2", other: "n" })
    refute_empty plural_entry_errors("pl", { one: "1", few: "2", many: "5" })
    refute_empty plural_entry_errors("ja", { one: "1", other: "n" })
    refute_empty plural_entry_errors("en", { few: "2", other: "n" })
    refute_empty plural_entry_errors("pl", { zero: "0", other: "n" })
    refute_empty plural_entry_errors("ro", { many: "5", other: "n" })
    refute_empty plural_entry_errors("he", { few: "3", other: "n" })
  end

  test "every plural key in the code has one and other forms in languages with :one" do
    _, ui_plurals = texts_in(Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,builder}")].reject { |path| path.include?("app/javascript") })
    _, js_plurals = texts_in(Dir[Rails.root.join("app/javascript/**/*.js")])

    { ui: ui_plurals, js: js_plurals }.each do |scope, plurals|
      keys = plurals.map(&:last).uniq
      (LANGUAGES - [ "fa" ]).each do |locale|
        next unless PLURAL_CATEGORIES.fetch(locale).include?(:one)

        missing = keys.reject do |key|
          entry = I18n.t(key, scope: scope, locale: locale, separator: Translation::SEPARATOR, default: nil)
          entry.is_a?(Hash) && entry[:one].is_a?(String) && entry[:other].is_a?(String)
        end
        assert_empty missing, "Add one/other forms in config/locales/#{locale}/#{scope}.yml for: #{missing.join(", ")}"
      end
    end
  end

  test "every one of the 24 locales has a plural rule matching its CLDR categories" do
    counts = [ 0, 1, 2, 3, 4, 5, 10, 11, 12, 14, 19, 20, 21, 22, 99, 100, 101, 102, 103, 111, 112, 120, 1_000_000, 1.5 ]

    with_available_locales(PLURAL_CATEGORIES.keys) do
      PLURAL_CATEGORIES.each do |locale, allowed|
        rule = I18n.t("i18n.plural.rule", locale: locale, resolve: false)
        assert_respond_to rule, :call, "Missing plural rule for #{locale}"
        seen = counts.map { |count| rule.call(count) }.uniq
        assert_empty seen - allowed, "#{locale} returned disallowed categories: #{seen - allowed}"
        assert_equal allowed.sort, seen.sort, "#{locale} categories mismatch"
      end
    end
  end

  test "translate_plural picks the language's CLDR form and falls back to other" do
    with_test_locale(:ar, ui: {
      "%{count} widgets" => {
        zero: "لا توجد ملفات",
        one: "ملف واحد",
        two: "ملفان",
        few: "%{count} ملفات",
        many: "%{count} ملفاً",
        other: "%{count} ملف"
      },
      "%{count} gadgets" => { one: "بطاقة واحدة", other: "%{count} بطاقة" }
    }) do
      assert_equal "لا توجد ملفات", Translation.translate_plural("%{count} widget", "%{count} widgets", 0)
      assert_equal "ملف واحد", Translation.translate_plural("%{count} widget", "%{count} widgets", 1)
      assert_equal "ملفان", Translation.translate_plural("%{count} widget", "%{count} widgets", 2)
      assert_equal "3 ملفات", Translation.translate_plural("%{count} widget", "%{count} widgets", 3)
      assert_equal "10 ملفات", Translation.translate_plural("%{count} widget", "%{count} widgets", 10)
      assert_equal "11 ملفاً", Translation.translate_plural("%{count} widget", "%{count} widgets", 11)
      assert_equal "99 ملفاً", Translation.translate_plural("%{count} widget", "%{count} widgets", 99)
      assert_equal "100 ملف", Translation.translate_plural("%{count} widget", "%{count} widgets", 100)
      assert_equal "101 ملف", Translation.translate_plural("%{count} widget", "%{count} widgets", 101)
      assert_equal "103 ملفات", Translation.translate_plural("%{count} widget", "%{count} widgets", 103)
      assert_equal "3.5 ملف", Translation.translate_plural("%{count} widget", "%{count} widgets", 3.5)
      assert_equal "0 بطاقة", Translation.translate_plural("%{count} gadget", "%{count} gadgets", 0)
      assert_equal "بطاقة واحدة", Translation.translate_plural("%{count} gadget", "%{count} gadgets", 1)
      assert_equal "5 بطاقة", Translation.translate_plural("%{count} gadget", "%{count} gadgets", 5)
    end

    with_test_locale(:pl, ui: {
      "%{count} files" => { one: "%{count} plik", few: "%{count} pliki", many: "%{count} plików", other: "%{count} pliku" },
      "%{count} cards" => { one: "%{count} karta", few: "%{count} karty", other: "%{count} kart" }
    }) do
      assert_equal "0 plików", Translation.translate_plural("%{count} file", "%{count} files", 0)
      assert_equal "1 plik", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "2 pliki", Translation.translate_plural("%{count} file", "%{count} files", 2)
      assert_equal "5 plików", Translation.translate_plural("%{count} file", "%{count} files", 5)
      assert_equal "12 plików", Translation.translate_plural("%{count} file", "%{count} files", 12)
      assert_equal "22 pliki", Translation.translate_plural("%{count} file", "%{count} files", 22)
      assert_equal "1.5 pliku", Translation.translate_plural("%{count} file", "%{count} files", 1.5)
      assert_equal "5 kart", Translation.translate_plural("%{count} card", "%{count} cards", 5)
    end

    with_test_locale(:uk, ui: {
      "%{count} files" => { one: "%{count} файл", few: "%{count} файли", many: "%{count} файлів", other: "%{count} файлу" }
    }) do
      assert_equal "1 файл", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "21 файл", Translation.translate_plural("%{count} file", "%{count} files", 21)
      assert_equal "11 файлів", Translation.translate_plural("%{count} file", "%{count} files", 11)
      assert_equal "2 файли", Translation.translate_plural("%{count} file", "%{count} files", 2)
      assert_equal "24 файли", Translation.translate_plural("%{count} file", "%{count} files", 24)
      assert_equal "5 файлів", Translation.translate_plural("%{count} file", "%{count} files", 5)
      assert_equal "1.5 файлу", Translation.translate_plural("%{count} file", "%{count} files", 1.5)
    end

    with_test_locale(:cs, ui: {
      "%{count} files" => { one: "%{count} soubor", few: "%{count} soubory", many: "%{count} souboru", other: "%{count} souborů" }
    }) do
      assert_equal "0 souborů", Translation.translate_plural("%{count} file", "%{count} files", 0)
      assert_equal "1 soubor", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "3 soubory", Translation.translate_plural("%{count} file", "%{count} files", 3)
      assert_equal "5 souborů", Translation.translate_plural("%{count} file", "%{count} files", 5)
      assert_equal "1.5 souboru", Translation.translate_plural("%{count} file", "%{count} files", 1.5)
    end

    with_test_locale(:ro, ui: {
      "%{count} files" => { one: "%{count} fișier", few: "%{count} fișiere", other: "%{count} de fișiere" }
    }) do
      assert_equal "0 fișiere", Translation.translate_plural("%{count} file", "%{count} files", 0)
      assert_equal "1 fișier", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "19 fișiere", Translation.translate_plural("%{count} file", "%{count} files", 19)
      assert_equal "20 de fișiere", Translation.translate_plural("%{count} file", "%{count} files", 20)
      assert_equal "101 de fișiere", Translation.translate_plural("%{count} file", "%{count} files", 101)
      assert_equal "102 fișiere", Translation.translate_plural("%{count} file", "%{count} files", 102)
      assert_equal "1.5 fișiere", Translation.translate_plural("%{count} file", "%{count} files", 1.5)
    end

    with_test_locale(:fr, ui: {
      "%{count} files" => { one: "%{count} fichier", other: "%{count} fichiers" }
    }) do
      assert_equal "0 fichier", Translation.translate_plural("%{count} file", "%{count} files", 0)
      assert_equal "1 fichier", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "2 fichiers", Translation.translate_plural("%{count} file", "%{count} files", 2)
      assert_equal "1000000 fichiers", Translation.translate_plural("%{count} file", "%{count} files", 1_000_000)
    end

    with_test_locale(:pt, ui: {
      "%{count} files" => { one: "%{count} arquivo", other: "%{count} arquivos" }
    }) do
      assert_equal "0 arquivo", Translation.translate_plural("%{count} file", "%{count} files", 0)
      assert_equal "1 arquivo", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "2 arquivos", Translation.translate_plural("%{count} file", "%{count} files", 2)
    end

    with_test_locale(:he, ui: {
      "%{count} files" => { one: "קובץ אחד", two: "שני קבצים", other: "%{count} קבצים" },
      "%{count} cards" => { one: "כרטיס אחד", other: "%{count} כרטיסים" }
    }) do
      assert_equal "קובץ אחד", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "שני קבצים", Translation.translate_plural("%{count} file", "%{count} files", 2)
      assert_equal "3 קבצים", Translation.translate_plural("%{count} file", "%{count} files", 3)
      assert_equal "2 כרטיסים", Translation.translate_plural("%{count} card", "%{count} cards", 2)
    end

    with_test_locale(:ja, ui: { "%{count} files" => { other: "%{count}件のファイル" } }) do
      assert_equal "1件のファイル", Translation.translate_plural("%{count} file", "%{count} files", 1)
      assert_equal "5件のファイル", Translation.translate_plural("%{count} file", "%{count} files", 5)
    end
  end

  test "for_scripts preserves plural hashes" do
    with_test_locale(:pl, js: { "%{count} files" => { one: "%{count} plik", few: "%{count} pliki", other: "%{count} plików" } }) do
      assert_equal({ one: "%{count} plik", few: "%{count} pliki", other: "%{count} plików" }, Translation.for_scripts["%{count} files"])
    end
  end

  test "every language has the formats dates and times are written in" do
    formats = I18n.t("date.formats", locale: :en).keys + I18n.t("time.formats", locale: :en).keys

    LANGUAGES.each do |locale|
      missing = formats.reject { |format| I18n.exists?("date.formats.#{format}", locale) || I18n.exists?("time.formats.#{format}", locale) }
      assert_empty missing, "Add these to config/locales/#{locale}.yml"
    end
  end

  test "English is the text as written" do
    assert_equal "Save changes", Translation.translate("Save changes")
    assert_equal "Delete Notes?", Translation.translate("Delete %{name}?", name: "Notes")
  end

  test "Persian translates, fills in values and writes Persian digits" do
    I18n.with_locale(:fa) do
      assert_equal "۳ فایل", Translation.translate_plural("%{count} file", "%{count} files", 3)
      assert_equal "Notes حذف شود؟", Translation.translate("Delete %{name}?", name: "Notes")
      assert_equal "A text nobody translated", Translation.translate("A text nobody translated")
    end
  end

  test "an html_safe value keeps its markup and the rest is escaped" do
    text = Translation.translate("%{name} <b>", name: ActiveSupport::SafeBuffer.new("<i>x</i>"))

    assert_equal "<i>x</i> &lt;b&gt;", text
    assert_predicate text, :html_safe?
  end

  test "the language a browser asks for" do
    assert_equal "fa", Translation.from_accept_language("fa-IR,fa;q=0.9,en;q=0.8")
    assert_equal "en", Translation.from_accept_language("vi-VN,en;q=0.5")
    assert_nil Translation.from_accept_language("vi-VN")
    assert_equal "pt", Translation.from_accept_language("pt-BR,pt;q=0.9")
    assert_equal "nl", Translation.from_accept_language("nl-NL,nl;q=0.9,en;q=0.8")
  end

  test "the language a browser asks for maps aliases" do
    available = %w[en nb he id zh]
    assert_equal "nb", Translation.from_accept_language("no", available: available)
    assert_equal "nb", Translation.from_accept_language("no-NO,en;q=0.5", available: available)
    assert_equal "nb", Translation.from_accept_language("nn-NO,en;q=0.5", available: available)
    assert_equal "nb", Translation.from_accept_language("nb-NO,en;q=0.5", available: available)
    assert_equal "he", Translation.from_accept_language("iw-IL,en;q=0.5", available: available)
    assert_equal "he", Translation.from_accept_language("iw", available: available)
    assert_equal "id", Translation.from_accept_language("in-ID,en;q=0.5", available: available)
    assert_equal "id", Translation.from_accept_language("in", available: available)
    assert_equal "zh", Translation.from_accept_language("zh-TW,en;q=0.5", available: available)
    assert_equal "zh", Translation.from_accept_language("zh-HK,en;q=0.5", available: available)
    assert_equal "zh", Translation.from_accept_language("zh-Hans-CN", available: available)
    assert_equal "nb", Translation.from_accept_language("en;q=0.5, nn;q=0.9", available: available)
    assert_equal "nb", Translation.from_accept_language("no-NO")
    assert_equal "zh", Translation.from_accept_language("zh-TW,en;q=0.5")
  end

  test "the language a browser asks for goes by its q-values" do
    assert_equal "fa", Translation.from_accept_language("en;q=0.1, fa;q=0.9")
    assert_equal "en", Translation.from_accept_language("fa;q=0, en")
    assert_equal "fa", Translation.from_accept_language("vi-VN, fa;q=0.5")
    assert_equal "en", Translation.from_accept_language("en, fa")
    assert_equal "fa", Translation.from_accept_language("fa;q=0.8, en;q=0.8")
    assert_equal "fa", Translation.from_accept_language("FA-ir;Q=1")
    assert_nil Translation.from_accept_language("fa;q=0, en;q=0.0")
    assert_nil Translation.from_accept_language(";;,,q=;garbage=1")
    assert_nil Translation.from_accept_language(nil)
  end

  test "direction follows the locale's translation.direction" do
    assert_equal "rtl", Translation.direction(:fa)
    assert_equal "ltr", Translation.direction(:en)
    with_test_locale(:ar, translation: { direction: "rtl" }) do
      assert_equal "rtl", Translation.direction(:ar)
      assert_predicate Translation, :rtl?
    end
    with_test_locale(:he, translation: { direction: "rtl" }) do
      assert_equal "rtl", Translation.direction(:he)
      assert_predicate Translation, :rtl?
    end
  end

  test "Jalali dates" do
    assert_equal [ 1404, 1, 1 ], Translation::Jalali.from(Date.new(2025, 3, 21))
    assert_equal [ 1403, 12, 30 ], Translation::Jalali.from(Date.new(2025, 3, 20))
    assert_equal [ 1405, 9, 3 ], Translation::Jalali.from(Date.new(2026, 11, 24))
    assert_equal [ 1399, 10, 11 ], Translation::Jalali.from(Date.new(2020, 12, 31))
  end

  test "a date is written in the language's calendar, by its formats and with its digits" do
    date = Date.new(2025, 9, 16)

    assert_equal "Tuesday, September 16, 2025", Translation.localize(date, :long_day)
    assert_equal [ 2025, 9, 16 ], Translation.date_parts(date)
    I18n.with_locale(:fa) do
      assert_equal "سه‌شنبه، ۲۵ شهریور ۱۴۰۴", Translation.localize(date, :long_day)
      assert_equal [ 1404, 6, 25 ], Translation.date_parts(date)
      assert_equal "۲۵", Translation.localize(date, :day_of_month)
    end
  end

  test "a clock is the language's" do
    time = Time.utc(2025, 9, 16, 18, 5)

    assert_equal "6:05 PM", Translation.localize(time, :clock)
    I18n.with_locale(:fa) { assert_equal "۱۸:۰۵", Translation.localize(time, :clock) }
  end

  private

  def texts_in(paths)
    texts, plurals = [], []
    paths.each do |path|
      source = File.read(path)
      source.scan(ONE) { |(text)| texts << unescape(text) }
      source.scan(TWO) { |one, other| plurals << [ unescape(one), unescape(other) ] }
    end
    [ texts.uniq, plurals.uniq ]
  end

  def words_in(paths)
    calls = paths.flat_map { |path| calls_of("words", File.read(path)) }
    calls.flat_map { |call| call.scan(/[:\[]\s*#{STRING}/).flatten }.map { |text| unescape(text) }.uniq
  end

  def calls_of(name, source)
    source.to_enum(:scan, /\b#{name}\(/).map do
      start = Regexp.last_match.end(0)
      depth, index = 1, start
      while depth.positive? && index < source.length
        depth += { "(" => 1, ")" => -1 }.fetch(source[index], 0)
        index += 1
      end
      source[start...(index - 1)]
    end
  end

  def unescape(text) = text.gsub(/\\(.)/) { { "n" => "\n", "t" => "\t" }.fetch($1, $1) }

  def translated?(locale, scope, text)
    I18n.t(text, scope: scope, locale: locale, separator: Translation::SEPARATOR, default: nil).is_a?(String)
  end

  def plural_translated?(locale, scope, text)
    entry = I18n.t(text, scope: scope, locale: locale, separator: Translation::SEPARATOR, default: nil)
    entry.is_a?(String) || (entry.is_a?(Hash) && entry[:other].is_a?(String))
  end

  def plural_entry_errors(locale, entry)
    errors = []
    errors << "missing :other" unless entry[:other].is_a?(String)
    errors << "non-string forms" unless entry.values.all?(String)
    disallowed = entry.keys.map(&:to_sym) - PLURAL_CATEGORIES.fetch(locale.to_s)
    errors << "disallowed categories: #{disallowed.join(", ")}" if disallowed.any?
    errors
  end

  def with_available_locales(locales)
    previous = I18n.available_locales
    I18n.available_locales = (previous + locales.map(&:to_sym)).uniq
    yield
  ensure
    I18n.available_locales = previous
  end

  def with_test_locale(locale, translations = nil)
    with_available_locales([ locale ]) do
      if translations
        I18n.backend.eager_load! unless I18n.backend.initialized?
        I18n.backend.store_translations(locale, translations)
      end
      I18n.with_locale(locale) { yield }
    ensure
      I18n.backend.reload! if translations
    end
  end
end
