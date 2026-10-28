# frozen_string_literal: true

require "test_helper"

class SyncAllCalendarsJobTest < ActiveJob::TestCase
  setup do
    @account = calendars_accounts(:icloud_account)
  end

  test "an account whose login was turned down is left alone for an hour, then tried again" do
    @account.mark_sync_error!(Calendars::Account::AUTHENTICATION_FAILED)

    SyncAllCalendarsJob.perform_now
    assert_not enqueued_jobs.any? { |job| job["job_class"] == "SyncCalendarsJob" && job["arguments"] == [ @account.id ] }

    travel 61.minutes do
      assert_enqueued_with(job: SyncCalendarsJob, args: [ @account.id ]) { SyncAllCalendarsJob.perform_now }
    end
  end
end
