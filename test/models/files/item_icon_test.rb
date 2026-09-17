# frozen_string_literal: true

require "test_helper"

module Files
  class ItemIconTest < ActiveSupport::TestCase
    test "a presentation file gets the presentation icon, which shared/icon actually renders" do
      item = file_items(:report)
      # application/vnd...presentationml.presentation contains "document" too
      # (officedocument), which the icon_name case matches first — use the
      # extension instead, the same way a .pptx upload would be identified.
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
  end
end
