# frozen_string_literal: true

class SyncAllEmailsJob < ApplicationJob
  queue_as :default
  skip_in_demo

  # A mailbox that hasn't synced for this long is reported, once until it syncs again
  STALLED = 2.hours

  class SyncStalled < StandardError; end

  def perform
    Mails::Account.find_each do |account|
      SyncEmailsJob.perform_later(account.id)
      report_stalled(account)
      account.tell_owners_of_stall
    end
  end

  private
    # A sync that fails shows on the mail page, which nobody may open for a day. This is
    # the error log's: a mailbox that stopped receiving mail is news, whatever stopped it.
    def report_stalled(account)
      return unless account.last_synced_at&.before?(STALLED.ago)

      Rails.cache.fetch([ "mail-sync-stalled", account.id, account.last_synced_at.to_i ], expires_in: 30.days) do
        Rails.error.report(SyncStalled.new("Mail account #{account.id} hasn't synced for over #{STALLED.inspect}"),
          handled: true, context: { mail_account_id: account.id, tool_id: account.tool_id,
                                    last_synced_at: account.last_synced_at, sync_error: account.sync_error })
        true
      end
    end
end
