# frozen_string_literal: true

require "test_helper"

module Calendars
  class CalendarTest < ActiveSupport::TestCase
    test "belongs to an account" do
      calendar = calendars_calendars(:personal)
      assert_equal calendars_accounts(:icloud_account), calendar.account
    end

    test "has many events" do
      calendar = calendars_calendars(:personal)
      assert_includes calendar.events, calendars_events(:meeting)
      assert_includes calendar.events, calendars_events(:all_day_event)
    end

    test "validates remote_id presence" do
      calendar = Calendars::Calendar.new(
        account: calendars_accounts(:icloud_account),
        name: "New Calendar"
      )
      assert_not calendar.valid?
      assert_includes calendar.errors[:remote_id], "can't be blank"
    end

    test "validates remote_id uniqueness within account" do
      existing = calendars_calendars(:personal)
      duplicate = Calendars::Calendar.new(
        account: existing.account,
        remote_id: existing.remote_id,
        name: "Duplicate"
      )

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:remote_id], "has already been taken"
    end

    test "allows same remote_id across different accounts" do
      calendar = Calendars::Calendar.new(
        account: calendars_accounts(:pending_account),
        remote_id: calendars_calendars(:personal).remote_id,
        name: "Same Remote ID"
      )

      assert calendar.valid?
    end

    test "validates name presence" do
      calendar = Calendars::Calendar.new(
        account: calendars_accounts(:icloud_account),
        remote_id: "/unique/path/"
      )
      assert_not calendar.valid?
      assert_includes calendar.errors[:name], "can't be blank"
    end

    test "enabled scope returns enabled calendars" do
      account = calendars_accounts(:icloud_account)

      enabled = account.calendars.enabled
      assert_includes enabled, calendars_calendars(:personal)
      assert_includes enabled, calendars_calendars(:work)
      assert_not_includes enabled, calendars_calendars(:disabled_calendar)
    end

    test "by_position scope orders by position" do
      account = calendars_accounts(:icloud_account)
      calendars = account.calendars.by_position

      assert_equal calendars_calendars(:personal), calendars.first
      assert_equal calendars_calendars(:work), calendars.second
    end

    test "color_hex returns color when present" do
      calendar = calendars_calendars(:personal)
      assert_equal "#3b82f6", calendar.color_hex
    end

    test "color_hex returns default color when color is blank" do
      calendar = calendars_calendars(:personal)
      calendar.color = nil
      assert_equal Calendars::Calendar::DEFAULT_COLOR, calendar.color_hex
    end

    test "setting is_default to true unsets other defaults" do
      personal = calendars_calendars(:personal)
      work = calendars_calendars(:work)

      assert personal.is_default?
      assert_not work.is_default?

      work.update!(is_default: true)

      assert work.reload.is_default?
      assert_not personal.reload.is_default?
    end

    test "destroys dependent events" do
      calendar = calendars_calendars(:personal)
      event_ids = calendar.events.pluck(:id)

      assert event_ids.any?

      calendar.destroy!

      event_ids.each do |id|
        assert_nil Calendars::Event.find_by(id: id)
      end
    end
  end
end
