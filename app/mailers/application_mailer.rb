class ApplicationMailer < ActionMailer::Base
  include Translation::Methods

  default from: -> { "#{Rails.application.config.x.app.name} <#{Rails.application.config.x.app.from_email}>" }
  helper :application
  helper :mailer
  layout "mailer"

  private

  # A mail is in the language of whoever reads it: the user it goes to, else (someone
  # not signed up yet) the language of who sent it
  def in_language_of(reader, fallback: nil, &block)
    locale = Translation.supported(reader.try(:locale)) || Translation.supported(fallback.try(:locale)) || I18n.default_locale
    I18n.with_locale(locale, &block)
  end
end
