# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    module Folders
      class DownloadsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @tool = tools(:my_files)
          @folder = file_folders(:documents)
          file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
          sign_in_as users(:one)
        end

        test "downloads the folder as a zip" do
          get tool_files_folder_download_path(@tool, @folder)

          assert_response :success
          assert_equal "application/zip", response.media_type
          assert_match "attachment", response.headers["Content-Disposition"]
          assert_match "Documents.zip", response.headers["Content-Disposition"]
          assert_equal({ "report.pdf" => "quarterly numbers" }, zip_contents(response.body))
        end

        test "a download is not recorded as the last visited path" do
          users(:one).update_column(:last_visited_path, tool_files_path(@tool))

          get tool_files_folder_download_path(@tool, @folder)

          assert_response :success
          assert_equal tool_files_path(@tool), users(:one).reload.last_visited_path
        end

        test "a folder over the budget sends the browser back to the listing" do
          stub_const(::Files::FolderArchive, :MAX_BYTES, 1) do
            get tool_files_folder_download_path(@tool, @folder)
          end

          assert_redirected_to tool_files_path(@tool)
          follow_redirect!
          assert_includes response.body, "Documents is too large to download as a zip."
        end

        test "a folder over the budget answers 413 outside the browser" do
          stub_const(::Files::FolderArchive, :MAX_FILES, 0) do
            get tool_files_folder_download_path(@tool, @folder), headers: { "Accept" => "*/*" }
          end

          assert_response :content_too_large
        end

        test "someone without access to the tool gets no zip" do
          sign_in_as users(:two)

          get tool_files_folder_download_path(@tool, @folder)

          assert_redirected_to root_path
        end

        private

        def zip_contents(data)
          zip = Zip::File.open_buffer(StringIO.new(data))
          zip.entries.to_h { |entry| [ entry.name, entry.get_input_stream.read ] }
        end
      end
    end
  end
end
