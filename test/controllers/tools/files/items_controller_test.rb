# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class ItemsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_files)
      end

      test "update moves a file into a folder of the same tool" do
        file = file_items(:readme)

        patch tool_files_item_path(@tool, file), params: { file: { folder_id: file_folders(:photos).id } }, as: :json

        assert_response :success
        assert_equal file_folders(:photos), file.reload.folder
      end

      test "a file can't be moved into a folder of another tool" do
        other_tool = Tool.create!(name: "Other Files", tool_type: tool_types(:files), owner: users(:two))
        foreign_folder = other_tool.file_folders.create!(name: "Theirs")
        file = file_items(:readme)

        patch tool_files_item_path(@tool, file), params: { file: { folder_id: foreign_folder.id } }, as: :json

        assert_nil file.reload.folder_id
        assert_empty foreign_folder.files
      end
    end
  end
end
