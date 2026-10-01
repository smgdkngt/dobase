# frozen_string_literal: true

class SyncAllCalendarsJob < ApplicationJob
  queue_as :default
  skip_in_demo

  def perform
    Calendars::Account.where.not(provider: "local").find_each do |account|
      # A rejected login waits for new settings or a sync by hand
      next if account.authentication_failed?

      SyncCalendarsJob.perform_later(account.id)
    end
  end
end
