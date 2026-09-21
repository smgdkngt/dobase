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

  test "two people write in the same document at once and both see everything" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"
    find("[data-document-editor-target='editor'] .ProseMirror").send_keys(:end, "One writes here.")

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.edit_tool_docs_document_path(tools(:shared_docs), docs_documents(:shared_notes))}')")
      wait_for_stimulus "document-editor"
      # What the other one typed arrives without a reload
      assert_selector ".ProseMirror", text: "One writes here."
      find("[data-document-editor-target='editor'] .ProseMirror").send_keys(:end, " Two writes here.")
    end

    assert_selector ".ProseMirror", text: "One writes here. Two writes here."
    assert_eventually { document.reload.content.to_plain_text.include?("Two writes here.") }
  end

  test "you can see where the other one is typing" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"

    using_session("colleague") do
      sign_in_as users(:two)
      assert_selector "aside.sidebar"
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.edit_tool_docs_document_path(tools(:shared_docs), docs_documents(:shared_notes))}')")
      wait_for_stimulus "document-editor"
      find("[data-document-editor-target='editor'] .ProseMirror").send_keys(:end, "Typing")
    end

    assert_selector ".collaboration-carets__caret"
    assert_selector ".collaboration-carets__label", text: users(:two).name, visible: :all
  end

  test "mentioning a colleague in a document tells them" do
    tool = tools(:shared_docs)
    document = docs_documents(:shared_notes)
    visit edit_tool_docs_document_path(tool, document)
    wait_for_stimulus "document-editor"

    find("[data-document-editor-target='editor'] .ProseMirror").send_keys(:end, "Over to @Us")
    find(".mention-suggestion-item", text: users(:two).name).click

    assert_selector "[data-document-editor-target='editor'] .mention", text: "@#{users(:two).name}"
    assert_eventually { users(:two).notifications.any? { |n| n.message == "User One mentioned you in Shared Notes" } }
  end

  private

  def assert_eventually(timeout: 5)
    deadline = Time.current + timeout
    sleep 0.1 until yield || Time.current > deadline
    assert yield, "condition wasn't met within #{timeout} seconds"
  end
end
