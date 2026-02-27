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
  end
end
