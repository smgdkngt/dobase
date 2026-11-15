# frozen_string_literal: true

class SyncDraftJob < ApplicationJob
  # The compose page saves a draft by itself every few seconds while someone writes. Its
  # copy on the mail server (which deletes the old copy and appends a new one) waits until
  # the writing has paused this long: each save asks for a copy that long after it, and a
  # copy asked for by a save that has been followed by another is left to that one.
  AUTOSAVE_WAIT = 30.seconds

  queue_as :default
  skip_in_demo
  # In turn with the other changes to its account's mail on the server (ImapSyncJob)
  limits_concurrency to: 1, key: ->(draft_id, *) { Mails::Message.where(id: draft_id).pick(:mail_account_id) || "draft-#{draft_id}" },
    **ImapSyncJob::ONE_ACCOUNT_AT_A_TIME
  # Tried again for a few minutes while the mail server can't be reached. The draft is
  # saved here either way.
  retry_on ImapSyncService::Unreachable, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.error("Gave up on saving draft #{job.arguments.first} on its mail server: #{error.message}")
  end

  # After a save of the compose page's own (Tools::Mails::DraftsController, autosave)
  def self.after_autosave(draft)
    set(wait: AUTOSAVE_WAIT).perform_later(draft.id, version: draft.sync_version)
  end

  # version: the save that asked for this copy (Mails::Message#sync_version). Without
  # one the draft is copied as it is now, whichever save that was.
  def perform(draft_id, version: nil)
    draft = Mails::Message.find_by(id: draft_id)
    # A draft discarded or sent before it got here stays off the server
    return unless draft&.draft? && !draft.trashed?
    # Saved again since: that save's copy comes after this one
    return if version && draft.sync_version != version

    ImapSyncService.new(draft.account).save_draft(draft)
  end
end
