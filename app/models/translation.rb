# frozen_string_literal: true

#   _("Save changes")
#   _("Delete %{name}?", name: tool.name)
#   n_("%{count} file", "%{count} files", 3)
#   Translation.localize(date, :day)
module Translation
  LANGUAGES = { "en" => "English", "nl" => "Nederlands", "de" => "Deutsch", "fr" => "Français", "es" => "Español", "pt" => "Português (Brasil)", "it" => "Italiano", "fa" => "فارسی" }.freeze
  ALIASES = { "no" => "nb", "nn" => "nb", "iw" => "he", "in" => "id" }.freeze

  SEPARATOR = "\u0001"

  module_function

  def locales = LANGUAGES.keys

  def supported(locale) = locale.to_s.presence_in(locales)

  def rtl?(locale = I18n.locale) = setting(:direction, locale) == "rtl"

  def direction(locale = I18n.locale) = rtl?(locale) ? "rtl" : "ltr"

  def from_accept_language(header, available: locales)
    ranges = header.to_s.split(",").filter_map.with_index do |part, index|
      range, *parameters = part.split(";").map(&:strip)
      next if range.blank?

      quality = 1.0
      parameters.each do |parameter|
        name, value = parameter.split("=", 2).map(&:strip)
        next unless name.casecmp?("q")

        quality = value.to_s.match?(/\A(0(\.\d{0,3})?|1(\.0{0,3})?)\z/) ? value.to_f : 0.0
      end
      [ range.downcase.split(/[-_]/).first, quality, index ] if quality.positive?
    end

    ranges.sort_by { |_, quality, index| [ -quality, index ] }.each do |code, _, _|
      found = ALIASES.fetch(code, code).presence_in(available)
      return found if found
    end
    nil
  end

  def translate(text, scope: :ui, **values)
    template = lookup(text, scope)
    interpolate(template, values)
  end

  def translate_plural(one, other, count, scope: :ui, **values)
    template = plural_template(other, count, scope) || (count == 1 ? one : other)
    interpolate(template, values.merge(count: count))
  end

  def plural_template(key, count, scope = :ui)
    return if I18n.locale.to_s == "en"

    found = I18n.t(key, scope: scope, separator: SEPARATOR, default: nil)
    case found
    when String then found
    when Hash
      selected = I18n.backend.pluralize(I18n.locale, found, count)
      selected.is_a?(String) ? selected : found[:other]
    end
  rescue I18n::InvalidPluralizationData
    found[:other] if found.is_a?(Hash) && found[:other].is_a?(String)
  end

  def lookup(text, scope = :ui)
    text = text.to_s
    return text if I18n.locale.to_s == "en" || text.empty?

    found = I18n.t(text, scope: scope, separator: SEPARATOR, default: nil)
    found.is_a?(String) ? found : text
  end

  def setting(name, locale = I18n.locale) = I18n.t(name, scope: :translation, locale: locale, default: nil)

  def digits(text)
    written = setting(:digits)
    written ? text.to_s.tr("0123456789", written) : text.to_s
  end

  def calendar(locale = I18n.locale)
    case setting(:calendar, locale)
    when "jalali" then Translation::Jalali
    end
  end

  def date_parts(date)
    calendar&.from(date) || [ date.year, date.month, date.day ]
  end

  def localize(value, format)
    pattern = (format_named(format, "time.formats") if value.respond_to?(:hour)) || format_named(format, "date.formats")
    raise ArgumentError, "No date or time format #{format}" unless pattern

    digits(I18n.l(value, format: in_calendar(pattern, value.to_date)))
  end

  def format_named(format, scope)
    I18n.t(format, scope: scope, default: nil) || I18n.t(format, scope: scope, locale: :en, default: nil)
  end

  def in_calendar(pattern, date)
    return pattern unless calendar

    year, month, day = date_parts(date)
    pattern.gsub(/%-?[YmdbB]/) do |directive|
      case directive
      when "%Y" then year.to_s
      when "%m" then month.to_s.rjust(2, "0")
      when "%-m" then month.to_s
      when "%d" then day.to_s.rjust(2, "0")
      when "%-d" then day.to_s
      when "%b", "%B" then setting(:month_names)[month]
      else directive
      end
    end
  end

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

  module Methods
    private

    def _(text, **values) = Translation.translate(text, **values)

    def n_(one, other, count, **values) = Translation.translate_plural(one, other, count, **values)
  end
end
