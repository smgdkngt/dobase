# frozen_string_literal: true

module Profiles
  # The zone times are shown in, switched from the offer a page makes when they are
  # shown in UTC and the browser is somewhere else (shared/time_zone_notice). Takes
  # the app's name for a zone or the browser's own. An account's setting: never a
  # token's.
  class TimeZonesController < ApplicationController
    def update
      zone = User.time_zone_for(params[:time_zone])

      if zone
        current_user.update!(timezone: zone)
        redirect_back_or_to root_path, notice: "Time zone set to #{zone}.", status: :see_other
      else
        redirect_back_or_to root_path, alert: "That time zone isn't one we know.", status: :see_other
      end
    end
  end
end
