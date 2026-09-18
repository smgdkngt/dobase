# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Shares
      class FilesControllerTest < ActionDispatch::IntegrationTest
        setup do
          @file = file_items(:report)
          @file.file.attach(io: StringIO.new("%PDF-1.4"), filename: "report.pdf", content_type: "application/pdf")
          @share = ::Files::Share.create!(shareable: file_folders(:documents), created_by: users(:one))
        end

        test "shows a file inside a shared folder" do
          get share_file_path(@share.token, @file)

          assert_response :success
          assert_includes response.body, @file.name
        end

        test "the file page downloads that file, not the whole folder" do
          get share_file_path(@share.token, @file)

          assert_select "a[href='#{share_file_download_path(@share.token, @file)}']", text: /Download/
          assert_select "a[href='#{share_download_path(@share.token)}']", count: 0
        end

        test "the gallery only offers images the share can actually open" do
          nested = file_items(:photo)
          nested.update!(folder: file_folders(:nested_folder))
          nested.file.attach(io: StringIO.new("jpeg"), filename: "sunset.jpg", content_type: "image/jpeg")

          get share_path(@share.token)

          assert_response :success
          assert_select "[data-name='#{nested.name}']", count: 0
        end

        test "a folder whose files are all in subfolders can still be downloaded" do
          @file.update!(folder: file_folders(:nested_folder))

          get share_path(@share.token)

          assert_response :success
          assert_select "a[href='#{share_download_path(@share.token)}']", text: /Download All/
        end

        test "a file that isn't in the shared folder shows the share's not found page" do
          get share_file_path(@share.token, file_items(:readme))

          assert_response :not_found
          assert_includes response.body, "Not Found"
        end

        test "a shared file has no file pages" do
          file_share = ::Files::Share.create!(shareable: @file, created_by: users(:one))

          get share_file_path(file_share.token, @file)

          assert_response :not_found
        end

        test "an expired folder link hides its files" do
          @share.update!(expires_at: 1.day.ago)

          get share_file_path(@share.token, @file)

          assert_response :gone
          assert_not_includes response.body, @file.name
        end

        test "a password-protected folder link hides its files until it is unlocked" do
          @share.update!(password: "correct horse")

          get share_file_path(@share.token, @file)

          assert_response :unauthorized
          assert_not_includes response.body, @file.name
          assert_not_includes response.body, "/rails/active_storage/"
        end
      end
    end
  end
end
