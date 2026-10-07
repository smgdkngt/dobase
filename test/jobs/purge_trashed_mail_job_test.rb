# frozen_string_literal: true

require "test_helper"

class PurgeTrashedMailJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @account = mails_accounts(:primary)
  end

  test "a trash that was emptied of old mail says so to the pages that have the mailbox open, and only then" do
    pages = PresenceChannel.broadcasting_for(@account.tool)
    trash(mails_messages(:inbox_read), 29.days.ago)
    assert_no_broadcasts(pages) { PurgeTrashedMailJob.perform_now }

    trash(mails_messages(:inbox_unread), 31.days.ago)
    assert_broadcasts(pages, 1) { PurgeTrashedMailJob.perform_now }
  end

  test "removes mail that has been in the trash for more than 30 days" do
    old = trash(mails_messages(:inbox_unread), 31.days.ago)
    recent = trash(mails_messages(:inbox_read), 29.days.ago)

    PurgeTrashedMailJob.perform_now

    assert_not Mails::Message.exists?(old.id)
    assert Mails::Message.exists?(recent.id)
    assert Mails::Message.where(trashed: false).exists?
  end

  test "leaves mail in the server's trash to the server" do
    in_server_trash = trash(mails_messages(:inbox_unread), 31.days.ago)
    in_server_trash.update_columns(folder: "Trash")

    PurgeTrashedMailJob.perform_now

    assert Mails::Message.exists?(in_server_trash.id)
  end

  private

  def trash(message, at)
    travel_to(at) { message.update!(trashed: true) }
    message
  end
end
