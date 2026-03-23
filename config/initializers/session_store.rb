# frozen_string_literal: true

Rails.application.config.session_store :cookie_store,
  key: "_#{Rails.application.config.x.app.name.parameterize}_session",
  same_site: :lax
