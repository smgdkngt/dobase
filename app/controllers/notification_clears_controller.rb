# frozen_string_literal: true

# Clearing them all, from the notifications page. Never a token's: it deletes.
class NotificationClearsController < ApplicationController
  def create
    current_user.notifications.delete_all

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "Notifications cleared." }
      format.any { head :ok }
    end
  end
end
