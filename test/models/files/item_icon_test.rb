# frozen_string_literal: true

require "test_helper"

module Files
  class ItemIconTest < ActiveSupport::TestCase
    test "a presentation file gets the presentation icon, which shared/icon actually renders" do
      item = file_items(:report)
      item.update!(name: "deck.pptx", content_type: "application/octet-stream")

      assert_equal "presentation", item.icon_name

      rendered = ApplicationController.render(
        partial: "shared/icon", locals: { name: item.icon_name, size: 16 }
      )
      # An unknown icon name silently falls back to "circle" — assert the
      # actual presentation glyph (its distinctive screen/pointer path) is
      # present, not a plain circle.
      assert_includes rendered, "M2 3h20"
    end

    test "office files get their icon from the content type alone" do
      item = file_items(:report)
      {
        "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "presentation",
        "application/vnd.ms-powerpoint" => "presentation",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "file-text",
        "application/msword" => "file-text",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "table"
      }.each do |content_type, icon|
        item.assign_attributes(name: "upload", content_type: content_type)

        assert_equal icon, item.icon_name, content_type
      end
    end
  end
end
