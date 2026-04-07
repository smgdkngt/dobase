# frozen_string_literal: true

class SyncDraftJob < ApplicationJob
  queue_as :default

  def perform(draft_id)
    draft = Mails::Message.find_by(id: draft_id)
    return unless draft&.draft?

    ImapSyncService.new(draft.account).save_draft(draft)
  end
end
