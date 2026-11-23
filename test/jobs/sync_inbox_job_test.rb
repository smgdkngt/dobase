# frozen_string_literal: true

require "test_helper"

class SyncInboxJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @account = mails_accounts(:primary)
    @synced = []
  end

  test "only the inbox is synced, and the page hears of what it brought" do
    assert_broadcast_on(pages, type: "changed", tool_id: @account.tool.id) do
      fresh = mails_messages(:inbox_read).dup
      sync_inbox { fresh.update!(message_id: "fresh@example.com", uid: 4711) }
    end
    assert_equal [ :inbox, [ :events, false ] ], @synced
  end

  test "an inbox that brought nothing says nothing" do
    assert_no_broadcasts(pages) { sync_inbox { } }
  end

  test "it waits for a sync of the same account that is running, where a second full sync is dropped" do
    assert_equal SyncEmailsJob.concurrency_group, SyncInboxJob.concurrency_group
    assert_equal :block, SyncInboxJob.concurrency_on_conflict
    assert_equal :discard, SyncEmailsJob.concurrency_on_conflict
    assert_equal SyncEmailsJob.new(@account.id).concurrency_key, SyncInboxJob.new(@account.id).concurrency_key
  end

  private
    def pages = PresenceChannel.broadcasting_for(@account.tool)

    def sync_inbox(&in_the_inbox)
      synced = @synced
      service = Object.new
      service.define_singleton_method(:sync_inbox) { |**| synced << :inbox; in_the_inbox.call }
      service.define_singleton_method(:record_events) { |complete:| synced << [ :events, complete ] }
      ImapSyncService.singleton_class.define_method(:new) { |*| service }
      SyncInboxJob.perform_now(@account.id)
    ensure
      ImapSyncService.singleton_class.remove_method(:new)
    end
end
