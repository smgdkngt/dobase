# frozen_string_literal: true

require "test_helper"

module Tools
  class FilesControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      @tool = tools(:my_files)
    end

    test "show renders files page with folders and files" do
      get tool_files_path(@tool)
      assert_response :success
      assert_includes response.body, "Documents"
      assert_includes response.body, "Photos"
      assert_includes response.body, "readme.txt"
    end

    test "show with folder_id renders subfolder contents" do
      get tool_files_path(@tool, folder_id: file_folders(:documents).id)
      assert_response :success
      assert_includes response.body, "report.pdf"
      assert_includes response.body, "Subfolder"
    end

    test "show with list view mode" do
      get tool_files_path(@tool, view: "list")
      assert_response :success
      assert_includes response.body, "readme.txt"
    end

    test "requires authentication" do
      sign_out
      get tool_files_path(@tool)
      assert_redirected_to new_session_path
    end

    test "show runs the same number of queries however many files and shares the folder has" do
      add_files = -> do
        4.times do
          name = "#{SecureRandom.hex(4)}.txt"
          item = @tool.file_items.create!(name: name, file: { io: StringIO.new("text"), filename: name, content_type: "text/plain" })
          ::Files::Share.create!(shareable: item, created_by: users(:one))
        end
        folder = @tool.file_folders.create!(name: "Shared #{SecureRandom.hex(4)}")
        ::Files::Share.create!(shareable: folder, created_by: users(:one))
      end

      assert_queries_independent_of(add_files) { get tool_files_path(@tool) }
    end
  end
end
