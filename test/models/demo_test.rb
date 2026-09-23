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

  test "a visitor gets three teammates of their own, on the team tools" do
    create_demo_tool_types
    visitor = in_demo_mode { Demo.create_visitor! }
    other = in_demo_mode { Demo.create_visitor! }

    teammates = Demo.teammates_of(visitor).order(:id)
    assert_equal [ "Marcus Rivera", "Priya Patel", "Jake Thompson" ], teammates.map(&:name)
    assert teammates.all? { |teammate| teammate.email_address.end_with?("@#{Demo::TEAM_DOMAIN}") }
    assert_empty teammates.ids & Demo.teammates_of(other).ids
    assert teammates.all? { |teammate| visitor.owned_tools.find_by!(name: "Team Chat").accessible_by?(teammate) }
    assert_not visitor.owned_tools.find_by!(name: "Team Chat").accessible_by?(Demo.teammates_of(other).first)
    assert_equal 2, Demo.visitors.count
    assert_not User.exists?(email_address: "marcus@moonshot-snacks.com")
  end

  test "a visitor and their teammates are one party, whoever asks" do
    create_demo_tool_types
    visitor = in_demo_mode { Demo.create_visitor! }
    marcus = Demo.teammates_of(visitor).find_by!(first_name: "Marcus")

    assert_equal 4, Demo.party_of(visitor).count
    assert_equal Demo.party_of(visitor).ids.sort, Demo.party_of(marcus).ids.sort
    assert_equal Demo.teammates_of(visitor).ids.sort, Demo.teammates_of(marcus).ids.sort
    assert_equal visitor, Demo.visitor_of(marcus)
    assert Demo.teammate?(marcus)
    assert_not Demo.teammate?(visitor)
    assert_empty Demo.party_of(users(:one))
    assert_empty Demo.party_of(nil)
  end

  test "the teammates come alive shortly after the visitor arrives" do
    create_demo_tool_types

    visitor = nil
    assert_enqueued_jobs 1, only: Demo::TeammatesJob do
      visitor = in_demo_mode { Demo.create_visitor! }
    end
    assert_enqueued_with job: Demo::TeammatesJob, args: [ visitor ]
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

  test "thumbnails of files already here are still made" do
    item = tools(:my_files).file_items.create!(name: "dot.png", created_by: users(:one), updated_by: users(:one))
    item.file.attach(io: file_fixture_png, filename: "dot.png", content_type: "image/png")

    in_demo_mode do
      variant = item.file.variant(resize_to_limit: [ 10, 10 ]).processed
      assert variant.image.attached?
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

  private

  def file_fixture_png
    require "zlib"
    row = "\x00" + "\xff\x00\x00".b * 2
    idat = Zlib::Deflate.deflate(row.b * 2)
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    StringIO.new("\x89PNG\r\n\x1A\n".b + chunk.call("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) + chunk.call("IDAT", idat) + chunk.call("IEND", ""))
  end
end
