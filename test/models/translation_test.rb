# frozen_string_literal: true

require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  STRING = /"((?:[^"\\]|\\.)*)"/
  ONE = /(?:(?<![\w.])_|Translation\.translate)\(\s*#{STRING}/
  TWO = /(?:(?<![\w.])n_|Translation\.translate_plural)\(\s*#{STRING}\s*,\s*#{STRING}/

  teardown { I18n.locale = :en }

  test "every text in the code has its Persian" do
    texts, plurals = texts_in(Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,builder}")].reject { |path| path.include?("app/javascript") })
    untranslated = texts.reject { |text| persian(:ui, text) } + plurals.map(&:last).reject { |other| persian(:ui, other) }

    assert_empty untranslated.uniq, "Add these to config/locales/fa/ui.yml"
  end

  # Kinds of tool are rows (db/seeds.rb), shown through ToolType#human_name and #human_description
  test "every kind of tool has its name and description in Persian" do
    texts = File.read(Rails.root.join("db/seeds.rb")).scan(/\{ name: #{STRING}, slug: .*description: #{STRING} \}/).flatten

    assert_equal 16, texts.size
    assert_empty texts.reject { |text| persian(:ui, text) }, "Add these to config/locales/fa/ui.yml"
  end

  test "every text a script shows has its Persian" do
    texts, plurals = texts_in(Dir[Rails.root.join("app/javascript/**/*.js")])
    untranslated = texts.reject { |text| persian(:js, text) } + plurals.map(&:last).reject { |other| persian(:js, other) }

    assert_empty untranslated.uniq, "Add these to config/locales/fa/js.yml"
  end

  test "a translation fills in the same values as its English" do
    I18n.with_locale(:fa) do
      %i[ui js].each do |scope|
        I18n.t(scope).each do |english, persian|
          assert_equal english.to_s.scan(/%\{\w+\}/).sort, persian.scan(/%\{\w+\}/).sort, "#{scope}: #{english}"
        end
      end
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
    assert_equal "شهریور", Translation::Jalali.month_name(Date.new(2025, 9, 16))
    assert_equal "سه‌شنبه", Translation::Jalali.weekday(Date.new(2025, 9, 16))
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

  def unescape(text) = text.gsub(/\\(.)/) { { "n" => "\n", "t" => "\t" }.fetch($1, $1) }

  def persian(scope, text)
    I18n.with_locale(:fa) { I18n.t(text, scope: scope, separator: Translation::SEPARATOR, default: nil) }.is_a?(String)
  end
end
