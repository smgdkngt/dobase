# frozen_string_literal: true

class SyncAllCalendarsJob < ApplicationJob
  queue_as :default

  def perform
    Calendars::Account.find_each do |account|
      SyncCalendarsJob.perform_later(account.id)
    end
  end
end
