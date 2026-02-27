# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Items
      class SharesControllerTest < ActionDispatch::IntegrationTest
        setup do
          sign_in_as users(:one)
          @tool = tools(:my_files)
          @file_with_share = file_items(:readme)
          @file_without_share = file_items(:report)
        end

        test "show for file with share returns share info in turbo frame" do
          get tool_files_item_share_path(@tool, @file_with_share)
          assert_response :success
          assert_includes response.body, "turbo-frame"
          assert_includes response.body, "share-content"
          assert_includes response.body, "Remove Share"
        end

        test "show for file without share returns create form in turbo frame" do
          get tool_files_item_share_path(@tool, @file_without_share)
          assert_response :success
          assert_includes response.body, "turbo-frame"
          assert_includes response.body, "share-content"
          assert_includes response.body, "Create Link"
        end

        test "create generates a share link" do
          assert_difference "::Files::Share.count", 1 do
            post tool_files_item_share_path(@tool, @file_without_share), params: { expires_at: 1.week.from_now.to_date }
          end
          assert_response :success
          assert_includes response.body, "turbo-frame"
          assert_includes response.body, "Remove Share"
        end

        test "create with password sets password" do
          post tool_files_item_share_path(@tool, @file_without_share), params: { password: "secret123" }
          assert_response :success
          share = @file_without_share.reload.share
          assert share.password_protected?
        end

        test "destroy removes share and redirects" do
          assert_difference "::Files::Share.count", -1 do
            delete tool_files_item_share_path(@tool, @file_with_share)
          end
          assert_redirected_to tool_files_item_path(@tool, @file_with_share)
        end
      end
    end
  end
end
