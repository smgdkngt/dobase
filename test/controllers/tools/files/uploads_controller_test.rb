# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class UploadsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_files)
        @folder = file_folders(:documents)
      end

      test "the upload form saves the files and redirects to their folder" do
        assert_difference "@folder.files.count", 2 do
          post tool_files_uploads_path(@tool), params: { folder_id: @folder.id, files: [ uploaded_file("one.txt"), uploaded_file("two.txt") ] }
        end
        assert_redirected_to tool_files_path(@tool, folder_id: @folder.id)
      end

      test "a refused upload saves nothing and redirects with an alert" do
        assert_no_difference "::Files::Item.count" do
          post tool_files_uploads_path(@tool), params: { folder_id: @folder.id, files: [ uploaded_file("one.txt"), uploaded_file("setup.exe") ] }
        end
        assert_redirected_to tool_files_path(@tool, folder_id: @folder.id)
        assert_equal "setup.exe: File type .exe is not allowed for security reasons", flash[:alert]
      end

      test "a dropped upload answers JSON" do
        post tool_files_uploads_path(@tool), params: { files: [ uploaded_file("one.txt") ] }, headers: { "Accept" => "application/json" }
        assert_response :created

        post tool_files_uploads_path(@tool), params: { files: [ uploaded_file("setup.exe") ] }, headers: { "Accept" => "application/json" }
        assert_response :unprocessable_entity
        assert_equal [ "setup.exe: File type .exe is not allowed for security reasons" ], response.parsed_body["errors"]
      end

      private

      def uploaded_file(name)
        Rack::Test::UploadedFile.new(StringIO.new("content of #{name}"), "application/octet-stream", original_filename: name)
      end
    end
  end
end
