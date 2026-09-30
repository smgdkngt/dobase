# frozen_string_literal: true

# Mail trashed on a server without a trash folder is deleted there right away. The copy
# in the trash here is kept for 30 days, as the trash says, and then removed. Mail in the
# server's trash leaves when the server empties its trash.
class PurgeTrashedMailJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days

  def perform
    Mails::Message.trashed.where.not(folder: Mails::Account::TRASH).where(trashed_at: ...RETENTION.ago).find_each(&:destroy)
  end
end
