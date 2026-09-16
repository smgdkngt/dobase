# frozen_string_literal: true

# Trashing mail already deletes it on the mail server. The copy in the trash is
# kept for 30 days, as the trash says, and then removed.
class PurgeTrashedMailJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days

  def perform
    Mails::Message.trashed.where(trashed_at: ...RETENTION.ago).find_each(&:destroy)
  end
end
