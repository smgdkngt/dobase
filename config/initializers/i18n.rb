# frozen_string_literal: true

require "i18n/backend/pluralization"

plural_fallback = Module.new do
  def pluralize(locale, entry, count)
    super
  rescue I18n::InvalidPluralizationData
    raise unless entry.is_a?(Hash) && entry.key?(:other)

    entry[:other]
  end
end

I18n::Backend::Simple.include(I18n::Backend::Pluralization)
I18n::Backend::Simple.include(plural_fallback)
