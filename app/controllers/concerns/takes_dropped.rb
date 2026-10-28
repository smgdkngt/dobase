# frozen_string_literal: true

# A create action that makes something of what was dragged onto its place (Dropped):
# `dropped` is the signed id the page gave the item that was dragged
module TakesDropped
  extend ActiveSupport::Concern

  private
    # What was dropped, when something was: nobody gets anything of what they can't see
    def dropped
      return if params[:dropped].blank?

      @dropped ||= Dropped.find(params[:dropped], user: current_user) || raise(ActiveRecord::RecordNotFound, "Nothing to drop")
    end
end
