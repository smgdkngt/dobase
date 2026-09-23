# frozen_string_literal: true

require "test_helper"

class DemoTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a visitor is known by the demo's address" do
    create_demo_tool_types
    visitor = in_demo_mode { Demo.create_visitor! }

    assert_includes Demo.visitors, visitor
    assert_not_includes Demo.visitors, users(:one)
    assert visitor.email_address.end_with?("@#{Demo::EMAIL_DOMAIN}")
  end

  test "mail and calendar servers are never reached" do
    in_demo_mode do
      assert_raises(RemoteHost::Forbidden) { RemoteHost.verify!("imap.example.com") }
    end
    assert_equal "imap.example.com", RemoteHost.verify!("imap.example.com")
  end

  test "server jobs are neither queued nor run" do
    in_demo_mode do
      assert_no_enqueued_jobs do
        SyncEmailsJob.perform_later(mails_accounts(:primary).id)
        SyncAllCalendarsJob.perform_later
      end

      assert_no_enqueued_jobs { SyncAllEmailsJob.perform_now }
    end

    assert_enqueued_jobs 1, only: SyncEmailsJob do
      SyncEmailsJob.perform_later(mails_accounts(:primary).id)
    end
  end

  test "the notification digest sends nothing in the demo" do
    in_demo_mode do
      assert_no_enqueued_jobs { NotificationDigestJob.perform_later }
    end
  end

  test "visitors can't upload files, but the example workspace brings its own" do
    blob = -> { ActiveStorage::Blob.new(filename: "a.txt", byte_size: 2, checksum: "x", content_type: "text/plain") }

    assert blob.call.valid?
    in_demo_mode do
      assert_not blob.call.valid?
      Demo.allowing_uploads { assert blob.call.valid? }
      assert_not blob.call.valid?
    end
  end
end
