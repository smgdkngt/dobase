class ApplicationMailer < ActionMailer::Base
  default from: -> { "#{Rails.application.config.x.app.name} <#{Rails.application.config.x.app.from_email}>" }
  layout "mailer"
end
