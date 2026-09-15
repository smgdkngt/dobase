# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class DeletionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @tool = tools(:my_files)
        @readme = file_items(:readme)
        @documents = file_folders(:documents)
        sign_in_as users(:one)
      end

      test "deletes the selected files and folders, with everything in the folders" do
        subfolder, report = file_folders(:nested_folder), file_items(:report)

        post tool_files_deletion_path(@tool), params: { file_ids: [ @readme.id ], folder_ids: [ @documents.id ] },
          headers: { "Referer" => tool_files_url(@tool, view: "list") }

        assert_redirected_to tool_files_url(@tool, view: "list")
        assert_not ::Files::Item.exists?(@readme.id)
        assert_not ::Files::Folder.exists?(@documents.id)
        assert_not ::Files::Folder.exists?(subfolder.id)
        assert_not ::Files::Item.exists?(report.id)
        assert ::Files::Folder.exists?(file_folders(:photos).id)
        assert ::Files::Item.exists?(file_items(:photo).id)
      end

      test "leaves items of another tool alone" do
        planted = ::Files::Item.create!(tool: tools(:project_board), name: "planted.txt")

        post tool_files_deletion_path(@tool), params: { file_ids: [ @readme.id, planted.id ] }

        assert_redirected_to tool_files_path(@tool)
        assert_not ::Files::Item.exists?(@readme.id)
        assert ::Files::Item.exists?(planted.id)
      end

      test "a selection with nothing left to delete is not found" do
        post tool_files_deletion_path(@tool), params: { file_ids: [ 0 ] }

        assert_redirected_to root_path
        assert_equal "That item no longer exists.", flash[:alert]
      end

      test "someone without access to the tool deletes nothing" do
        sign_in_as users(:two)

        assert_no_difference -> { ::Files::Item.count } do
          post tool_files_deletion_path(@tool), params: { file_ids: [ @readme.id ], folder_ids: [ @documents.id ] }
        end

        assert_redirected_to root_path
      end
    end
  end
end
