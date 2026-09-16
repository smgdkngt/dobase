# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Shares
      class DownloadsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @file = file_items(:readme)
          @file.file.attach(io: StringIO.new("hello world"), filename: "readme.txt", content_type: "text/plain")
          @share = file_shares(:readme_share)
        end

        test "downloads a shared file" do
          assert_difference -> { @share.reload.download_count }, 1 do
            get share_download_path(@share.token)
          end

          assert_response :success
          assert_match "attachment", response.headers["Content-Disposition"]
          assert_equal "hello world", response.body
        end

        test "an unknown link is not found" do
          get share_download_path("no-such-token")

          assert_response :not_found
        end

        test "an expired link does not download" do
          @share.update!(expires_at: 1.day.ago)

          assert_no_difference -> { @share.reload.download_count } do
            get share_download_path(@share.token)
          end

          assert_response :gone
          assert_not_includes response.body, "hello world"
        end

        test "a password-protected link does not download until it is unlocked" do
          @share.update!(password: "correct horse")

          assert_no_difference -> { @share.reload.download_count } do
            get share_download_path(@share.token)
          end

          assert_response :unauthorized
          assert_includes response.body, "Password Required"
          assert_not_includes response.body, "hello world"
        end

        test "a password-protected link downloads after it is unlocked" do
          @share.update!(password: "correct horse")
          post share_unlock_path(@share.token), params: { password: "correct horse" }

          get share_download_path(@share.token)

          assert_response :success
          assert_equal "hello world", response.body
        end

        test "downloads a shared folder as a zip" do
          folder_share = share_documents

          assert_difference -> { folder_share.reload.download_count }, 1 do
            get share_download_path(folder_share.token)
          end

          assert_response :success
          assert_equal "application/zip", response.media_type
          assert_match "Documents.zip", response.headers["Content-Disposition"]
          assert_equal({ "report.pdf" => "quarterly numbers" }, zip_contents(response.body))
        end

        test "a shared folder over the budget explains instead of downloading" do
          folder_share = share_documents

          assert_no_difference -> { folder_share.reload.download_count } do
            stub_const(::Files::FolderArchive, :MAX_BYTES, 1) do
              get share_download_path(folder_share.token)
            end
          end

          assert_response :content_too_large
          assert_includes response.body, "Too Large to Download"
          assert_includes response.body, share_path(folder_share.token)
        end

        private

        def share_documents
          file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
          ::Files::Share.create!(shareable: file_folders(:documents), created_by: users(:one))
        end

        def zip_contents(data)
          zip = Zip::File.open_buffer(StringIO.new(data))
          zip.entries.to_h { |entry| [ entry.name, entry.get_input_stream.read ] }
        end
      end
    end
  end
end
