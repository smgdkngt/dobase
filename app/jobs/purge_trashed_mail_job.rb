# frozen_string_literal: true

# Mail trashed on a server without a trash folder is deleted there right away. The copy
# in the trash here is kept for 30 days, as the trash says, and then removed. Mail in the
# server's trash leaves when the server empties its trash.
class PurgeTrashedMailJob < ApplicationJob
  queue_as :default

  RETENTION = 30.days

  def perform
    old = Mails::Message.trashed.where.not(folder: Mails::Account::TRASH).where(trashed_at: ...RETENTION.ago)
    emptied = Tool.where(id: Mails::Account.where(id: old.select(:mail_account_id)).select(:tool_id)).to_a
    old.find_each(&:destroy)
    # A trash that is open somewhere shows it (Tool#announce_change)
    emptied.each(&:announce_change)
  end
end
