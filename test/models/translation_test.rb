# frozen_string_literal: true

require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  STRING = /"((?:[^"\\]|\\.)*)"/
  ONE = /(?:(?<![\w.])_|Translation\.translate)\(\s*#{STRING}/
  TWO = /(?:(?<![\w.])n_|Translation\.translate_plural)\(\s*#{STRING}\s*,\s*#{STRING}/
  # Every language but English, whose texts are the keys
  LANGUAGES = Translation.locales - [ "en" ]

  teardown { I18n.locale = :en }

  test "every text in the code has its translation in every language" do
    texts, plurals = texts_in(Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,builder}")].reject { |path| path.include?("app/javascript") })

    LANGUAGES.each do |locale|
      untranslated = texts.reject { |text| translated?(locale, :ui, text) } + plurals.map(&:last).reject { |other| translated?(locale, :ui, other) }
      assert_empty untranslated.uniq, "Add these to config/locales/#{locale}/ui.yml"
    end
  end

  # Kinds of tool are rows (db/seeds.rb), shown through ToolType#human_name and #human_description
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
      untranslated = texts.reject { |text| translated?(locale, :js, text) } + plurals.map(&:last).reject { |other| translated?(locale, :js, other) }
      assert_empty untranslated.uniq, "Add these to config/locales/#{locale}/js.yml"
    end
  end

  test "a translation fills in the same values as its English" do
    LANGUAGES.each do |locale|
      %i[ui js].each do |scope|
        I18n.t(scope, locale: locale).each do |english, translated|
          assert_equal english.to_s.scan(/%\{\w+\}/).sort, translated.scan(/%\{\w+\}/).sort, "#{locale} #{scope}: #{english}"
        end
      end
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
    assert_equal "en", Translation.from_accept_language("de-DE,en;q=0.5")
    assert_nil Translation.from_accept_language("de-DE")
  end

  test "Persian reads right to left" do
    assert_equal "rtl", Translation.direction(:fa)
    assert_equal "ltr", Translation.direction(:en)
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

  # The texts a view names for the reader's browser to write (ApplicationHelper#words):
  # the strings in a `words(…)` that follow a `:` or a `[`, which are the texts, not the
  # attributes they go in
  def words_in(paths)
    calls = paths.flat_map { |path| calls_of("words", File.read(path)) }
    calls.flat_map { |call| call.scan(/[:\[]\s*#{STRING}/).flatten }.map { |text| unescape(text) }.uniq
  end

  # The arguments of every call to a method in a source, its parentheses balanced
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
end
