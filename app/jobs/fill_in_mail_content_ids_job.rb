# frozen_string_literal: true

# Once, for mail saved before attachments kept their Content-IDs (bin/rails mail:fill_in_content_ids)
class FillInMailContentIdsJob < ApplicationJob
  queue_as :default
  skip_in_demo

  def perform(mail_account_id)
    account = Mails::Account.find_by(id: mail_account_id)
    ImapSyncService.new(account).fill_in_content_ids if account
  end
end
