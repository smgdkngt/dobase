# frozen_string_literal: true

# Sends errors to a Sentry-compatible collector, and does nothing at all unless
# SENTRY_DSN is set — a self-hoster who doesn't want it never notices it's here.
#
#   SENTRY_DSN     the collector's address (Bugsink, GlitchTip, Sentry, ...)
#   SENTRY_ENV     what to call this installation, defaults to the Rails environment
#   KAMAL_VERSION  set by Kamal; reported as the release, so an error names its deploy
module ErrorReporting
  # Errors Rails answers for by itself: a request for something that isn't there,
  # a request that was never valid. They're answers, not faults.
  ALREADY_HANDLED = %w[
    ActiveRecord::RecordNotFound
    ActionController::RoutingError
    ActionController::BadRequest
    ActionController::ParameterMissing
    ActionController::InvalidAuthenticityToken
    ActionController::UnknownFormat
    ActionDispatch::Http::MimeNegotiation::InvalidType
  ].freeze

  def self.dsn
    ENV["SENTRY_DSN"].presence
  end

  def self.enabled?
    dsn.present?
  end

  def self.configure!
    return unless enabled?

    Sentry.init do |config|
      config.dsn = dsn
      config.environment = ENV["SENTRY_ENV"].presence || Rails.env
      config.release = ENV["KAMAL_VERSION"].presence
      config.breadcrumbs_logger = [ :active_support_logger ]
      config.excluded_exceptions += ALREADY_HANDLED
      # Errors only: no performance traces, and nothing personal beyond who hit it.
      config.traces_sample_rate = 0.0
      config.send_default_pii = false
      config.before_send = ->(event, _hint) { scrub(event) }
    end
  end

  # Rails already filters passwords and tokens out of its own logs; the same list
  # keeps them out of an error report.
  def self.scrub(event)
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    event.request&.data = filter.filter(event.request.data) if event.request&.data.is_a?(Hash)
    event
  end
end
