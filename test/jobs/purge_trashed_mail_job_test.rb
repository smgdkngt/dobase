# frozen_string_literal: true

require "test_helper"

class PurgeTrashedMailJobTest < ActiveJob::TestCase
  setup do
    @account = mails_accounts(:primary)
  end

  test "removes mail that has been in the trash for more than 30 days" do
    old = trash(mails_messages(:inbox_unread), 31.days.ago)
    recent = trash(mails_messages(:inbox_read), 29.days.ago)

    PurgeTrashedMailJob.perform_now

    assert_not Mails::Message.exists?(old.id)
    assert Mails::Message.exists?(recent.id)
    assert Mails::Message.where(trashed: false).exists?
  end

  private

  def trash(message, at)
    travel_to(at) { message.update!(trashed: true) }
    message
  end
end
