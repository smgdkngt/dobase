# frozen_string_literal: true

require "test_helper"

module Files
  class TextPreviewTest < ActiveSupport::TestCase
    setup { @tool = tools(:my_files) }

    def upload(name, content, content_type: "text/plain")
      @tool.file_items.create!(name: name, file: { io: StringIO.new(content), filename: name, content_type: content_type })
    end

    test "text files are shown as text" do
      item = upload("notes.txt", "Hello there")

      assert item.text?
      assert_not item.markdown?
      assert_equal "Hello there", item.preview_text
    end

    test "a markdown file is markdown, whatever its content type says" do
      item = upload("README.md", "# Title", content_type: "application/octet-stream")

      assert item.text?
      assert item.markdown?
    end

    test "an image is not text" do
      item = upload("photo.png", "\x89PNG\r\n", content_type: "image/png")

      assert_not item.text?
    end

    test "a file too large to show says so instead of loading it" do
      item = upload("big.log", "x")
      item.update_column(:file_size, Files::Item::MAX_PREVIEW_BYTES + 1)

      assert item.preview_too_large?
      assert_nil item.preview_text
    end

    test "a file that only claims to be text has nothing to show" do
      item = upload("broken.txt", "\xff\xfe\x00binary")

      assert item.text?
      assert_nil item.preview_text
    end
  end
end
