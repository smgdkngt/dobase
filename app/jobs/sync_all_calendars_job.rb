# frozen_string_literal: true

class SyncAllCalendarsJob < ApplicationJob
  queue_as :default
  skip_in_demo

  def perform
    Calendars::Account.where.not(provider: "local").find_each do |account|
      next if account.waiting_after_refused_login?

      SyncCalendarsJob.perform_later(account.id)
    end
  end
end
