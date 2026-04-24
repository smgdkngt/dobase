# frozen_string_literal: true

require "test_helper"

module Calendars
  class AccountTest < ActiveSupport::TestCase
    test "belongs to a tool" do
      account = calendars_accounts(:icloud_account)
      assert_equal tools(:my_calendar), account.tool
    end

    test "has many calendars" do
      account = calendars_accounts(:icloud_account)
      assert_includes account.calendars, calendars_calendars(:personal)
      assert_includes account.calendars, calendars_calendars(:work)
    end

    test "has many events through calendars" do
      account = calendars_accounts(:icloud_account)
      assert_includes account.events, calendars_events(:meeting)
    end

    test "validates username presence" do
      account = Calendars::Account.new(
        tool: tools(:my_calendar),
        encrypted_password: "encrypted",
        caldav_url: "https://caldav.example.com"
      )
      assert_not account.valid?
      assert_includes account.errors[:username], "can't be blank"
    end

    test "validates encrypted_password presence" do
      account = Calendars::Account.new(
        tool: tools(:my_calendar),
        username: "user@example.com",
        caldav_url: "https://caldav.example.com"
      )
      assert_not account.valid?
      assert_includes account.errors[:encrypted_password], "can't be blank"
    end

    test "local account saves without username or password" do
      tool = Tool.create!(
        name: "Local-only calendar",
        tool_type: tool_types(:calendar),
        owner: users(:one)
      )
      account = Calendars::Account.new(tool: tool, provider: "local", sync_status: "pending")

      assert account.save, account.errors.full_messages.to_sentence
      assert_nil account.password
      assert_nil account.username
      assert_nil account.encrypted_password
    end

    test "encrypts and decrypts password" do
      account = calendars_accounts(:icloud_account)
      account.password = "new-secret-password"
      account.save!

      # Reload to ensure it was persisted
      account.reload
      assert_equal "new-secret-password", account.password
    end

    test "password returns nil for blank encrypted_password" do
      account = Calendars::Account.new
      assert_nil account.password
    end

    test "validates sync_status inclusion" do
      account = calendars_accounts(:icloud_account)

      %w[pending syncing synced error].each do |status|
        account.sync_status = status
        assert account.valid?, "Expected #{status} to be valid"
      end

      account.sync_status = "invalid"
      assert_not account.valid?
    end

    test "synced? returns true when sync_status is synced" do
      account = calendars_accounts(:icloud_account)
      account.sync_status = "synced"
      assert account.synced?
    end

    test "syncing? returns true when sync_status is syncing" do
      account = calendars_accounts(:icloud_account)
      account.sync_status = "syncing"
      assert account.syncing?
    end

    test "sync_error? returns true when sync_status is error" do
      account = calendars_accounts(:icloud_account)
      account.sync_status = "error"
      assert account.sync_error?
    end

    test "mark_syncing! updates status and clears error" do
      account = calendars_accounts(:icloud_account)
      account.update!(sync_status: "error", sync_error: "Previous error")

      account.mark_syncing!

      assert_equal "syncing", account.sync_status
      assert_nil account.sync_error
    end

    test "mark_synced! updates status and last_synced_at" do
      account = calendars_accounts(:pending_account)

      freeze_time do
        account.mark_synced!

        assert_equal "synced", account.sync_status
        assert_equal Time.current, account.last_synced_at
        assert_nil account.sync_error
      end
    end

    test "mark_sync_error! updates status and error message" do
      account = calendars_accounts(:icloud_account)

      account.mark_sync_error!("Connection timeout")

      assert_equal "error", account.sync_status
      assert_equal "Connection timeout", account.sync_error
    end

    test "needs_sync scope returns pending and error accounts" do
      icloud = calendars_accounts(:icloud_account)
      pending = calendars_accounts(:pending_account)

      icloud.update!(sync_status: "synced")
      pending.update!(sync_status: "pending")

      needs_sync = Calendars::Account.needs_sync
      assert_includes needs_sync, pending
      assert_not_includes needs_sync, icloud
    end

    test "synced scope returns synced accounts" do
      icloud = calendars_accounts(:icloud_account)
      pending = calendars_accounts(:pending_account)

      icloud.update!(sync_status: "synced")
      pending.update!(sync_status: "pending")

      synced = Calendars::Account.synced
      assert_includes synced, icloud
      assert_not_includes synced, pending
    end

    test "destroys dependent calendars" do
      account = calendars_accounts(:icloud_account)
      calendar_ids = account.calendars.pluck(:id)

      assert calendar_ids.any?

      account.destroy!

      calendar_ids.each do |id|
        assert_nil Calendars::Calendar.find_by(id: id)
      end
    end
  end
end
