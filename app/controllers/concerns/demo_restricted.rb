# frozen_string_literal: true

# What reaches outside the app — sending mail, connecting to mail and calendar servers,
# public links, invitations — is switched off in the demo:
#
#   restrict_in_demo only: :create
module DemoRestricted
  extend ActiveSupport::Concern

  REFUSAL = "That's switched off in the demo."

  class_methods do
    def restrict_in_demo(**options)
      before_action :refuse_in_demo, **options
    end
  end

  private

  def refuse_in_demo
    return unless Demo.enabled?

    respond_to do |format|
      format.json { render json: { error: "Not available in the demo" }, status: :forbidden }
      # A form in a modal or a frame stays where it is, and the page says why
      format.turbo_stream do
        flash.now[:alert] = REFUSAL
        render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash"), status: :forbidden
      end
      format.any { redirect_back_or_to root_path, alert: REFUSAL }
    end
  end
end
