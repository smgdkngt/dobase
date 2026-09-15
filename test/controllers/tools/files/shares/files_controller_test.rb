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
