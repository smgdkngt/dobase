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

      test "create past the maximum depth redirects with an alert" do
        parent = file_folders(:nested_folder)
        parent.update_column(:depth, ::Files::Folder::MAX_DEPTH - 1)

        assert_no_difference "::Files::Folder.count" do
          post tool_files_folders_path(@tool), params: { name: "Too deep", parent_id: parent.id }
        end
        assert_redirected_to tool_files_path(@tool, folder_id: parent.id)
        assert_equal "Maximum folder depth of 10 reached", flash[:alert]
      end

      test "update renames folder" do
        folder = file_folders(:documents)
        patch tool_files_folder_path(@tool, folder), params: { folder: { name: "Renamed" } }, as: :json
        assert_response :success
        assert_equal "Renamed", folder.reload.name
      end

      test "dropping a folder on the home breadcrumb moves it to the top level" do
        folder = file_folders(:nested_folder)
        patch tool_files_folder_path(@tool, folder), params: { folder: { parent_id: nil } }, as: :json
        assert_response :success
        assert_nil folder.reload.parent_id
      end

      test "dropping a folder into its own subfolder leaves it where it is" do
        folder = file_folders(:documents)
        patch tool_files_folder_path(@tool, folder), params: { folder: { parent_id: file_folders(:nested_folder).id.to_s } }, as: :json
        assert_response :unprocessable_entity
        assert_nil folder.reload.parent_id
      end

      test "a folder can't be moved into a folder of another tool" do
        other_tool = Tool.create!(name: "Other Files", tool_type: tool_types(:files), owner: users(:two))
        foreign_folder = other_tool.file_folders.create!(name: "Theirs")
        folder = file_folders(:photos)

        patch tool_files_folder_path(@tool, folder), params: { folder: { parent_id: foreign_folder.id } }, as: :json

        assert_nil folder.reload.parent_id
        assert_empty foreign_folder.children
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
