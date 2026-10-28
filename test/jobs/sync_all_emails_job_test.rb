# frozen_string_literal: true

require "test_helper"

class SyncAllEmailsJobTest < ActiveJob::TestCase
  setup do
    @account = mails_accounts(:primary)
    Mails::Account.where.not(id: @account.id).update_all(last_synced_at: Time.current)
  end

  test "asks every mailbox for a sync" do
    assert_enqueued_with(job: SyncEmailsJob, args: [ @account.id ]) { SyncAllEmailsJob.perform_now }
  end

  test "a mailbox that hasn't synced for hours is reported once, whatever stopped it" do
    @account.update!(last_synced_at: 3.hours.ago, sync_status: "error", sync_error: Mails::Account::AUTHENTICATION_FAILED)

    with_cache do
      assert_error_reported(SyncAllEmailsJob::SyncStalled) { SyncAllEmailsJob.perform_now }
      assert_no_error_reported { SyncAllEmailsJob.perform_now }

      # Synced again and stalled again later: news again
      @account.update!(last_synced_at: 150.minutes.ago)
      assert_error_reported(SyncAllEmailsJob::SyncStalled) { SyncAllEmailsJob.perform_now }
    end
  end

  test "a mailbox that synced lately, or never did, isn't reported" do
    @account.update!(last_synced_at: 10.minutes.ago)
    assert_no_error_reported { SyncAllEmailsJob.perform_now }

    @account.update!(last_synced_at: nil)
    assert_no_error_reported { SyncAllEmailsJob.perform_now }
  end

  private
    def with_cache
      previous, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous
    end
end
