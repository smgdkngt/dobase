# frozen_string_literal: true

Rails.application.config.x.app = ActiveSupport::OrderedOptions.new
Rails.application.config.x.app.name = ENV.fetch("APP_NAME", "Dobase")
Rails.application.config.x.app.logo_path = ENV.fetch("APP_LOGO_PATH", "/icon.svg")
Rails.application.config.x.app.host = ENV.fetch("APP_HOST", "localhost:3000")
# MAILER_FROM_ADDRESS is what ONCE calls the sender set on its email settings screen
Rails.application.config.x.app.from_email = ENV["APP_FROM_EMAIL"].presence || ENV["MAILER_FROM_ADDRESS"].presence || "notifications@dobase.co"
