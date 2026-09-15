# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class SharesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @file = file_items(:readme)
        @share = file_shares(:readme_share)
      end

      test "shows a shared file" do
        get share_path(@share.token)

        assert_response :success
        assert_includes response.body, @file.name
      end

      test "an unknown link is not found" do
        get share_path("no-such-token")

        assert_response :not_found
        assert_includes response.body, "Not Found"
      end

      test "an expired link says so and hides the file" do
        @share.update!(expires_at: 1.day.ago)

        get share_path(@share.token)

        assert_response :gone
        assert_includes response.body, "Link Expired"
        assert_not_includes response.body, @file.name
      end

      test "a password-protected link asks for the password and hides the file" do
        @share.update!(password: "correct horse")

        get share_path(@share.token)

        assert_response :unauthorized
        assert_includes response.body, "Password Required"
        assert_not_includes response.body, @file.name
      end

      test "a wrong password keeps the link locked" do
        @share.update!(password: "correct horse")

        get share_path(@share.token), params: { password: "battery staple" }

        assert_response :unauthorized
        assert_includes response.body, "Incorrect password"
        assert_not_includes response.body, @file.name
      end

      test "the right password unlocks the link" do
        @share.update!(password: "correct horse")

        get share_path(@share.token), params: { password: "correct horse" }

        assert_response :success
        assert_includes response.body, @file.name
      end
    end
  end
end
