# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Shares
      module Files
        class DownloadsControllerTest < ActionDispatch::IntegrationTest
          setup do
            @file = file_items(:report)
            @file.file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
            @share = ::Files::Share.create!(shareable: file_folders(:documents), created_by: users(:one))
          end

          test "downloads one file of a shared folder" do
            assert_difference -> { @share.reload.download_count }, 1 do
              get share_file_download_path(@share.token, @file)
            end

            assert_response :success
            assert_equal "quarterly numbers", response.body
            assert_match 'attachment; filename="report.pdf"', response.headers["Content-Disposition"]
          end

          test "a file outside the shared folder isn't served" do
            outside = file_items(:readme)
            outside.file.attach(io: StringIO.new("top secret"), filename: "readme.txt", content_type: "text/plain")

            get share_file_download_path(@share.token, outside)

            assert_response :not_found
            assert_includes response.body, "Not Found"
            assert_not_includes response.body, "top secret"
          end

          test "a locked folder link doesn't hand out its files" do
            @share.update!(password: "correct horse")

            get share_file_download_path(@share.token, @file)

            assert_response :unauthorized
            assert_not_includes response.body, "quarterly numbers"
          end

          test "a shared file has no files inside it" do
            file_share = ::Files::Share.create!(shareable: @file, created_by: users(:one))

            get share_file_download_path(file_share.token, @file)

            assert_response :not_found
          end
        end
      end
    end
  end
end
