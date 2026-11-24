# frozen_string_literal: true

# The languages the interface is in, and the one way a text of it is translated.
#
# A text is written in English where it is used, as it always was, and handed to `_`:
#
#   _("Save changes")                          # => "ذخیرهٔ تغییرات" in Persian
#   _("Delete %{name}?", name: tool.name)      # interpolated like I18n
#   _("%{link} changed it", link: link_to(…))  # an html_safe value keeps its markup
#   n_("%{count} file", "%{count} files", 3)   # one or the other, by the count
#
# The English is the key (as with gettext): config/locales/fa.yml holds each one under
# `ui:` with its Persian, and a text without one stays English. Texts that a script
# shows are under `js:` and reach the page in the <head> (services/i18n.js).
# test/models/translation_test.rb fails on a text in the code that has no Persian.
#
# The JSON API and anything an access token asks for stay English: what reads them
# is a program (the CLI, an agent), which expects the words it was written against.
module Translation
  LANGUAGES = { "en" => "English", "fa" => "فارسی" }.freeze
  RIGHT_TO_LEFT = %w[fa].freeze

  # Keys are whole sentences, dots and all: a separator no text has
  SEPARATOR = "\u0001"
  PERSIAN_DIGITS = "۰۱۲۳۴۵۶۷۸۹"

  module_function

  def locales = LANGUAGES.keys

  def supported(locale) = locale.to_s.presence_in(locales)

  def rtl?(locale = I18n.locale) = RIGHT_TO_LEFT.include?(locale.to_s)

  def direction(locale = I18n.locale) = rtl?(locale) ? "rtl" : "ltr"

  # The language a browser asks for first, of the ones there are
  def from_accept_language(header)
    header.to_s.split(",").map { |part| part.split(";").first.to_s.strip.downcase[0, 2] }.find { |code| supported(code) }
  end

  def translate(text, scope: :ui, **values)
    template = lookup(text, scope)
    interpolate(template, values)
  end

  def translate_plural(one, other, count, scope: :ui, **values)
    template = I18n.locale.to_s == "en" ? nil : I18n.t(other, scope: scope, separator: SEPARATOR, default: nil)
    template ||= count == 1 ? one : other
    interpolate(template, values.merge(count: count))
  end

  def lookup(text, scope = :ui)
    text = text.to_s
    return text if I18n.locale.to_s == "en" || text.empty?

    found = I18n.t(text, scope: scope, separator: SEPARATOR, default: nil)
    found.is_a?(String) ? found : text
  end

  # 0-9 as the language writes them
  def digits(text)
    rtl? ? text.to_s.tr("0123456789", PERSIAN_DIGITS) : text.to_s
  end

  # The texts the browser's scripts show, in this language (services/i18n.js)
  def for_scripts
    return {} if I18n.locale.to_s == "en"

    I18n.t(:js, default: {}).transform_keys(&:to_s)
  end

  def interpolate(template, values)
    return template if values.empty?

    values = values.transform_values { |value| value.is_a?(Numeric) ? digits(value) : value }
    if values.values.any? { |value| value.respond_to?(:html_safe?) && value.html_safe? }
      escaped = values.transform_values { |value| ERB::Util.html_escape(value) }
      I18n.interpolate(ERB::Util.html_escape(template).to_str, escaped).html_safe
    else
      I18n.interpolate(template, values)
    end
  end

  # `_` and `n_` wherever a text is written: views, controllers, models, mailers,
  # notifiers and jobs include this
  module Methods
    private

    def _(text, **values) = Translation.translate(text, **values)

    def n_(one, other, count, **values) = Translation.translate_plural(one, other, count, **values)
  end
end
