# frozen_string_literal: true

require "application_system_test_case"

class DocsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_docs)
    @document = docs_documents(:meeting_notes)
    sign_in_as users(:one)
  end

  test "text typed just before leaving the editor is saved" do
    visit edit_tool_docs_document_path(@tool, @document)
    wait_for_turbo
    wait_for_stimulus "document-editor"

    find("[data-document-editor-target='editor'] .ProseMirror").send_keys(:end, " Written at the last second")
    # Leave well within the two-second autosave delay
    find(".sidebar a", text: "My Files").click
    assert_selector "h1", text: "My Files"

    assert_eventually { @document.reload.content.to_plain_text.include?("Written at the last second") }
  end

  test "the editor shows its own placeholder" do
    visit edit_tool_docs_document_path(@tool, docs_documents(:empty_document))
    wait_for_turbo

    assert_selector "[data-document-editor-target='editor'] .ProseMirror [data-placeholder='Start writing...']"
  end

  private

  def assert_eventually(timeout: 5)
    deadline = Time.current + timeout
    sleep 0.1 until yield || Time.current > deadline
    assert yield, "condition wasn't met within #{timeout} seconds"
  end
end
