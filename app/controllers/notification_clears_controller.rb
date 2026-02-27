# frozen_string_literal: true

class NotificationClearsController < ApplicationController
  def create
    current_user.notifications.delete_all
    head :ok
  end
end
