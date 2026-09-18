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
  end
end
