# frozen_string_literal: true

class SyncDraftJob < ApplicationJob
  queue_as :default
  skip_in_demo
  # Tried again for a few minutes while the mail server can't be reached. The draft is
  # saved here either way.
  retry_on ImapSyncService::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.error("Gave up on saving draft #{job.arguments.first} on its mail server: #{error.message}")
  end

  def perform(draft_id)
    draft = Mails::Message.find_by(id: draft_id)
    # A draft discarded before it got here stays off the server
    return unless draft&.draft? && !draft.trashed?

    ImapSyncService.new(draft.account).save_draft(draft)
  end
end
