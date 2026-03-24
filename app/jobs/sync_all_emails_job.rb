# frozen_string_literal: true

class SyncAllEmailsJob < ApplicationJob
  queue_as :default

  def perform
    Mails::Account.find_each do |account|
      SyncEmailsJob.perform_later(account.id)
    end
  end
end
