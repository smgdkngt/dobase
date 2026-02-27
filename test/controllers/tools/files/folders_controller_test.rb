# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class FoldersControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_files)
      end

      test "create makes a new folder" do
        assert_difference "::Files::Folder.count", 1 do
          post tool_files_folders_path(@tool), params: { name: "New Folder" }
        end
        assert_redirected_to tool_files_path(@tool)
      end

      test "create with parent_id makes nested folder" do
        parent = file_folders(:documents)
        assert_difference "::Files::Folder.count", 1 do
          post tool_files_folders_path(@tool), params: { name: "Nested", parent_id: parent.id }
        end
        folder = ::Files::Folder.last
        assert_equal parent.id, folder.parent_id
      end

      test "update renames folder" do
        folder = file_folders(:documents)
        patch tool_files_folder_path(@tool, folder), params: { folder: { name: "Renamed" } }, as: :json
        assert_response :success
        assert_equal "Renamed", folder.reload.name
      end

      test "destroy removes folder" do
        folder = file_folders(:photos)
        assert_difference "::Files::Folder.count", -1 do
          delete tool_files_folder_path(@tool, folder)
        end
      end
    end
  end
end
