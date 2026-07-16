# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Items
      class DownloadsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @user = users(:one)
          @tool = tools(:my_files)
          @file = file_items(:readme)
          @file.file.attach(io: StringIO.new("hello world"), filename: "readme.txt", content_type: "text/plain")
          sign_in_as @user
        end

        test "downloads the file as an attachment" do
          get tool_files_item_download_path(@tool, @file)

          assert_response :success
          assert_match "attachment", response.headers["Content-Disposition"]
          assert_equal "hello world", response.body
        end

        test "a download is not recorded as the last visited path" do
          @user.update_column(:last_visited_path, tool_files_path(@tool))

          get tool_files_item_download_path(@tool, @file)

          assert_response :success
          # The navigational files path stays; the download must not overwrite it.
          assert_equal tool_files_path(@tool), @user.reload.last_visited_path
        end
      end
    end
  end
end
