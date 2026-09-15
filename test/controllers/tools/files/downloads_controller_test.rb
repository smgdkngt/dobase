# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class DownloadsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @tool = tools(:my_files)
        @readme = file_items(:readme)
        @documents = file_folders(:documents)
        @readme.file.attach(io: StringIO.new("read me first"), filename: "readme.txt", content_type: "text/plain")
        file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
        sign_in_as users(:one)
      end

      test "downloads several items as one zip" do
        post tool_files_download_path(@tool), params: { file_ids: [ @readme.id ], folder_ids: [ @documents.id ] }

        assert_response :success
        assert_equal "application/zip", response.media_type
        assert_match "attachment", response.headers["Content-Disposition"]
        assert_match "My Files.zip", response.headers["Content-Disposition"]
        assert_equal({ "readme.txt" => "read me first", "Documents/report.pdf" => "quarterly numbers" }, zip_contents(response.body))
      end

      test "one file downloads on its own" do
        post tool_files_download_path(@tool), params: { file_ids: [ @readme.id ] }

        assert_redirected_to tool_files_item_download_path(@tool, @readme)
      end

      test "one folder downloads as its own zip" do
        post tool_files_download_path(@tool), params: { folder_ids: [ @documents.id ] }

        assert_redirected_to tool_files_folder_download_path(@tool, @documents)
      end

      test "leaves out items of another tool" do
        planted = ::Files::Item.create!(tool: tools(:project_board), name: "planted.txt",
          file: { io: StringIO.new("not yours"), filename: "planted.txt", content_type: "text/plain" })

        post tool_files_download_path(@tool), params: { file_ids: [ @readme.id, planted.id ], folder_ids: [ @documents.id ] }

        assert_response :success
        assert_equal [ "Documents/report.pdf", "readme.txt" ], zip_contents(response.body).keys.sort
      end

      test "a selection with nothing left to download is not found" do
        post tool_files_download_path(@tool), params: { file_ids: [ 0 ] }

        assert_redirected_to root_path
        assert_equal "That item no longer exists.", flash[:alert]
      end

      test "a selection over the budget goes back to the listing" do
        stub_const(::Files::FolderArchive, :MAX_FILES, 1) do
          post tool_files_download_path(@tool), params: { file_ids: [ @readme.id ], folder_ids: [ @documents.id ] },
            headers: { "Referer" => tool_files_url(@tool, folder_id: @documents.id) }
        end

        assert_redirected_to tool_files_url(@tool, folder_id: @documents.id)
        follow_redirect!
        assert_includes response.body, "The selection is too large to download as a zip."
      end

      test "someone without access to the tool gets no zip" do
        sign_in_as users(:two)

        post tool_files_download_path(@tool), params: { file_ids: [ @readme.id ], folder_ids: [ @documents.id ] }

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
