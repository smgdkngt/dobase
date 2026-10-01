# frozen_string_literal: true

require "test_helper"

module Docs
  class DocumentTest < ActiveSupport::TestCase
    include ActionCable::TestHelper

    test "belongs to a tool" do
      document = docs_documents(:meeting_notes)
      assert_equal tools(:my_docs), document.tool
    end

    test "validates title presence" do
      document = Docs::Document.new(tool: tools(:my_docs), title: "")
      assert_not document.valid?
      assert_includes document.errors[:title], "can't be blank"
    end

    test "created_by and updated_by are optional" do
      document = docs_documents(:empty_document)
      assert_nil document.created_by
      assert_nil document.updated_by
      assert document.valid?
    end

    test "can be assigned created_by and updated_by" do
      document = docs_documents(:empty_document)
      user = users(:one)

      document.created_by = user
      document.updated_by = user
      document.save!

      document.reload
      assert_equal user, document.created_by
      assert_equal user, document.updated_by
    end

    test "has rich text content" do
      document = docs_documents(:meeting_notes)
      assert_respond_to document, :content
    end

    test "preview_text returns empty string when content is blank" do
      document = docs_documents(:empty_document)
      assert_equal "", document.preview_text
    end

    test "preview_html turns links into spans" do
      document = docs_documents(:empty_document)
      document.content = %(<p>See <a href="https://example.com">this page</a> for more.</p>)

      preview = Nokogiri::HTML5.fragment(document.preview_html)

      assert_empty preview.css("a")
      assert_equal "this page", preview.at_css("span").text
      assert_empty preview.at_css("span").attribute_nodes
      assert_predicate document.preview_html, :html_safe?
    end

    test "preview_html closes what the cut-off left open" do
      document = docs_documents(:empty_document)
      document.content = "<ul>#{"<li><strong>A point worth making</strong></li>" * 100}</ul>"

      preview = document.preview_html

      assert_operator preview.length, :<, 1600
      assert_equal preview, Nokogiri::HTML5.fragment(preview).to_html
      assert preview.end_with?("</div>")
    end

    # The sanitizer leaves < and > as they are inside an attribute, so a title
    # or an alt can hold text that looks like a tag.
    test "preview_html makes no element or attribute out of text inside an attribute" do
      [
        %q(<a href="https://example.com" title="><img src=x onerror=alert(1)>">link</a>),
        %q(<a href="https://example.com" title="<a onmouseover=alert(1) ">link</a>),
        %q(<img src="https://example.com/a.png" alt="<a onmouseover=alert(1) x=">),
        %q(<img alt="<a href='x'><script>alert(1)</script>" src="https://example.com/a.png">),
        %q(<p title="</a><img src=x onerror=alert(1)>">text</p>),
        %q(<p title='" onmouseover="alert(1)'>text</p>)
      ].each do |hostile|
        document = docs_documents(:empty_document)
        document.content = hostile

        preview = Nokogiri::HTML5.fragment(document.preview_html)

        assert_empty preview.css("script, a"), "for #{hostile}"
        assert_equal 1, preview.css("span, img, p").size, "for #{hostile}"
        preview.css("*").each do |node|
          assert_empty node.attribute_nodes.map(&:name) - %w[class src alt title], "for #{hostile}"
        end
      end
    end

    test "preview_html stays safe wherever the cut-off lands" do
      hostile = %q(<p title="><img src=x onerror=alert(1)>">text</p>)
      document = docs_documents(:empty_document)

      (0..hostile.length).each do |padding|
        document.content = "<p>#{"a" * (1500 - 60 - padding)}</p>#{hostile}"

        preview = Nokogiri::HTML5.fragment(document.preview_html)

        assert_empty preview.css("img"), "with #{padding} characters less"
        assert_empty preview.css("[onerror]"), "with #{padding} characters less"
      end
    end

    test "locked? returns false when not locked" do
      document = docs_documents(:meeting_notes)
      document.locked_by_id = nil
      document.locked_at = nil
      assert_not document.locked?
    end

    test "locked? returns true when recently locked" do
      document = docs_documents(:meeting_notes)
      document.locked_by = users(:one)
      document.locked_at = 1.minute.ago
      assert document.locked?
    end

    test "locked? returns false when lock expired" do
      document = docs_documents(:meeting_notes)
      document.locked_by = users(:one)
      document.locked_at = 10.minutes.ago
      assert_not document.locked?
    end

    test "edited_at is when the content last changed, not when the lock was taken" do
      document = docs_documents(:project_plan)
      edited_at = document.last_edited_at
      document.update!(locked_by: users(:one), locked_at: Time.current)

      assert_equal edited_at, document.edited_at
      assert_operator document.updated_at, :>, document.edited_at
    end

    test "edited_at falls back to updated_at for documents never edited" do
      document = docs_documents(:empty_document)

      assert_equal document.updated_at, document.edited_at
    end
    test "ordered lists the most recently edited documents first" do
      tool = tools(:my_docs)
      edited = tool.documents.create!(title: "Edited", created_by: users(:one), last_edited_at: 1.minute.ago)
      touched = tool.documents.create!(title: "Only touched", created_by: users(:one), last_edited_at: 1.day.ago)
      touched.touch

      assert_equal [ edited, touched ], tool.documents.ordered.where(id: [ edited, touched ]).to_a
    end

    test "throwing the shared copy away starts a new one and tells the open editors" do
      document = docs_documents(:meeting_notes)
      document.updates.create!(data: "\x01")

      assert_broadcast_on(DocumentSyncChannel.broadcasting_for(document), type: "replaced", generation: 1) do
        assert_difference -> { document.reload.shared_copy_generation }, 1 do
          document.reset_shared_copy!
        end
      end

      assert_empty document.updates
    end

    test "throwing the shared copy away doesn't count as an edit" do
      document = docs_documents(:empty_document)

      assert_no_changes -> { document.reload.edited_at } do
        document.reset_shared_copy!
      end
    end
  end
end
