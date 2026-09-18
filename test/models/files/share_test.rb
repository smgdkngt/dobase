# frozen_string_literal: true

require "test_helper"

module Files
  class ShareTest < ActiveSupport::TestCase
    setup { @file = file_items(:readme) }

    test "a share set to expire on a day lasts until the end of that day" do
      travel_to Time.zone.local(2030, 9, 16, 9) do
        share = @file.create_share!(created_by: users(:one), expires_at: "2030-09-17")

        assert_equal Time.zone.local(2030, 9, 17).end_of_day.to_fs(:db), share.expires_at.to_fs(:db)
        assert share.active?
      end

      travel_to Time.zone.local(2030, 9, 17, 23, 30) { assert_not @file.share.reload.expired? }
      travel_to Time.zone.local(2030, 9, 18, 0, 30) { assert @file.share.reload.expired? }
    end

    test "an exact expiry time is kept as it is" do
      share = @file.create_share!(created_by: users(:one), expires_at: Time.zone.local(2030, 1, 15, 12))

      assert_equal Time.zone.local(2030, 1, 15, 12), share.expires_at
    end
  end
end
