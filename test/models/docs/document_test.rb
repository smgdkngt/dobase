# frozen_string_literal: true

require "test_helper"

module Docs
  class DocumentTest < ActiveSupport::TestCase
    test "belongs to a tool" do
      document = docs_documents(:meeting_notes)
      assert_equal tools(:my_docs), document.tool
    end

    test "validates title presence" do
      document = Docs::Document.new(tool: tools(:my_docs), title: "")
      assert_not document.valid?
      assert_includes document.errors[:title], "can't be blank"
    end

    test "last_edited_by is optional" do
      document = docs_documents(:empty_document)
      assert_nil document.last_edited_by
      assert document.valid?
    end

    test "can be assigned last_edited_by" do
      document = docs_documents(:empty_document)
      user = users(:one)

      document.last_edited_by = user
      document.last_edited_at = Time.current
      document.save!

      assert_equal user, document.reload.last_edited_by
    end

    test "has rich text content" do
      document = docs_documents(:meeting_notes)
      assert_respond_to document, :content
    end

    test "preview_text returns empty string when content is blank" do
      document = docs_documents(:empty_document)
      assert_equal "", document.preview_text
    end

    test "ordered scope sorts by updated_at descending" do
      documents = Docs::Document.ordered
      assert documents.first.updated_at >= documents.last.updated_at
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
  end
end
