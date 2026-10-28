# frozen_string_literal: true

require "test_helper"

class SyncStallNoticeTest < ActiveSupport::TestCase
  setup do
    @mail = mails_accounts(:primary)
    @tool = @mail.tool
    @tool.collaborators.create!(user: users(:two), role: "collaborator")
  end

  test "a mailbox a day without a sync is told to its tool's owners once" do
    @mail.update!(last_synced_at: 25.hours.ago, sync_status: "error", sync_error: Mails::Account::AUTHENTICATION_FAILED)

    assert_difference -> { users(:one).notifications.count }, 1 do
      @mail.tell_owners_of_stall
      @mail.tell_owners_of_stall
    end
    assert_equal 0, users(:two).notifications.count

    notification = users(:one).notifications.last
    assert_match "Mail for testuser@example.com hasn't synced since", notification.message
    assert_match Mails::Account::AUTHENTICATION_FAILED, notification.message
    assert_equal "/tools/#{@tool.id}/edit?tab=email", notification.url
  end

  test "a mailbox that synced again and stalled again is told again" do
    @mail.update!(last_synced_at: 25.hours.ago)
    @mail.tell_owners_of_stall

    @mail.update!(last_synced_at: 26.hours.ago + 1.minute)
    assert_difference -> { users(:one).notifications.count }, 1 do
      @mail.tell_owners_of_stall
    end
  end

  test "a mailbox that synced today, or never did, is told to nobody" do
    @mail.update!(last_synced_at: 23.hours.ago)
    @mail.tell_owners_of_stall
    @mail.update!(last_synced_at: nil)
    @mail.tell_owners_of_stall

    assert_equal 0, Noticed::Event.where(type: "SyncStalledNotifier").count
  end

  test "a calendar a day without a sync is told to its owners, with a link to its settings" do
    calendar = calendars_accounts(:icloud_account)
    calendar.update!(last_synced_at: 2.days.ago)

    calendar.tell_owners_of_stall
    calendar.tell_owners_of_stall

    notifications = Noticed::Event.where(type: "SyncStalledNotifier").flat_map(&:notifications)
    assert_equal 1, notifications.size
    assert_match "The calendar hasn't synced since", notifications.first.message
    assert_equal "/tools/#{calendar.tool_id}/edit?tab=calendar", notifications.first.url
  end

  test "the scheduled syncs tell the owners of stalled accounts" do
    @mail.update!(last_synced_at: 25.hours.ago)
    calendars_accounts(:icloud_account).update!(last_synced_at: 25.hours.ago)

    SyncAllEmailsJob.perform_now
    SyncAllCalendarsJob.perform_now

    assert_equal 2, Noticed::Event.where(type: "SyncStalledNotifier").count
  end
end
