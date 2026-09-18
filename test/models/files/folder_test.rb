# frozen_string_literal: true

require "test_helper"

module Files
  class FolderTest < ActiveSupport::TestCase
    setup do
      @documents = file_folders(:documents)
      @photos = file_folders(:photos)
      @subfolder = file_folders(:nested_folder)
    end

    test "moving a folder moves its whole subtree down with it" do
      grandchild = @documents.tool.file_folders.create!(name: "Deeper", parent: @subfolder)

      @documents.update!(parent: @photos)

      assert_equal 1, @documents.reload.depth
      assert_equal 2, @subfolder.reload.depth
      assert_equal 3, grandchild.reload.depth
    end

    test "moving a folder back to the top raises its subtree with it" do
      @documents.update!(parent: @photos)
      @documents.update!(parent: nil)

      assert_equal 0, @documents.reload.depth
      assert_equal 1, @subfolder.reload.depth
    end

    test "a subtree can't be moved past the maximum depth" do
      @photos.update_column(:depth, ::Files::Folder::MAX_DEPTH - 2)

      assert_not @documents.update(parent: @photos)
      assert_equal 0, @documents.reload.depth
    end
  end
end
