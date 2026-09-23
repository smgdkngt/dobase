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

  test "uploads stay small" do
    assert_equal 200.megabytes, Demo.upload_limit(200.megabytes)

    in_demo_mode do
      assert_equal 10.megabytes, Demo.upload_limit(200.megabytes)
      assert_equal 5.megabytes, Demo.upload_limit(5.megabytes)

      blob = ActiveStorage::Blob.new(filename: "big.bin", byte_size: 11.megabytes, checksum: "x", content_type: "application/octet-stream")
      assert_not blob.valid?
    end
  end

  test "a file over the demo's limit is refused" do
    item = tools(:my_files).file_items.new(name: "big.bin", created_by: users(:one), updated_by: users(:one))
    item.file.attach(io: StringIO.new("x" * (Demo::MAX_UPLOAD_SIZE + 1)), filename: "big.bin")

    assert item.valid?
    in_demo_mode { assert_not item.valid? }
    assert_includes item.errors[:file], "is too large. Maximum size is 10MB"
  end
end
