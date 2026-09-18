# frozen_string_literal: true

require "test_helper"

module Tools
  module Files
    class ThumbnailsTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_files)
      end

      def upload(name, content_type: "image/png")
        @tool.file_items.create!(name: name, file: {
          io: File.open(Rails.root.join("test/fixtures/files/sample.png")), filename: name, content_type: content_type
        })
      end

      test "the grid shows a thumbnail, not the original" do
        photo = upload("holiday.png")

        get tool_files_path(@tool, view: "grid")

        assert_response :success
        assert_match %r{/rails/active_storage/representations/}, response.body
        assert_no_match %r{/rails/active_storage/blobs/[^"]*holiday\.png}, response.body
      end

      test "an image page shows a display copy, not the original" do
        photo = upload("holiday.png")

        get tool_files_item_path(@tool, photo)

        assert_response :success
        assert_match %r{/rails/active_storage/representations/}, response.body
        assert_no_match %r{<img[^>]*/rails/active_storage/blobs/}, response.body
      end

      test "a picture vips can't read is shown as it is" do
        drawing = @tool.file_items.create!(name: "logo.svg", file: {
          io: StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'></svg>"), filename: "logo.svg", content_type: "image/svg+xml"
        })

        assert_equal drawing.file, drawing.thumbnail
        assert_equal drawing.file, drawing.display_copy
      end
    end
  end
end
