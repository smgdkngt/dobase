# frozen_string_literal: true

# What reaches outside the app — sending mail, connecting to mail and calendar servers,
# public links, invitations — is switched off in the demo:
#
#   restrict_in_demo only: :create
module DemoRestricted
  extend ActiveSupport::Concern

  REFUSAL = "That's switched off in the demo."
  SLOW_DOWN = "You're going a bit fast for the demo. Try again in a minute."

  included do
    # A visitor clicks; a script floods. Every change counts, across the whole app.
    rate_limit to: 60, within: 1.minute, scope: "demo-changes", by: -> { Current.user&.id || request.remote_ip },
      if: -> { Demo.enabled? && !request.get? && !request.head? },
      with: -> { refuse_in_demo(SLOW_DOWN, status: :too_many_requests) }
  end

  class_methods do
    def restrict_in_demo(**options)
      before_action :refuse_in_demo, **options
    end
  end

  private

  def refuse_in_demo(message = REFUSAL, status: :forbidden)
    return unless Demo.enabled?

    respond_to do |format|
      format.json { render json: { error: status == :forbidden ? "Not available in the demo" : message }, status: status }
      # A form in a modal or a frame stays where it is, and the page says why
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash"), status: status
      end
      format.any { redirect_back_or_to root_path, alert: message }
    end
  end
end
