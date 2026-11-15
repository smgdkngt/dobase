# frozen_string_literal: true

require "application_system_test_case"

class DocumentViewerTest < ApplicationSystemTestCase
  test "a crafted editor name in the lock status renders as text, not markup" do
    user = users(:one)
    document = docs_documents(:meeting_notes)
    sign_in_as(user)
    visit tool_docs_document_path(document.tool, document)
    wait_for_turbo
    wait_for_stimulus "document-viewer"

    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='document-viewer']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "document-viewer")
      controller.showLocked('<img src=x onerror="window.__xss = true">Evil Editor')
    JS

    assert_no_selector "[data-document-viewer-target='lockStatus'] img"
    assert_nil page.evaluate_script("window.__xss")
    assert_text "Evil Editor is editing"
  end

  test "someone else in the editor is shown, and you can still join them" do
    document = docs_documents(:shared_notes)
    document.update_columns(locked_by_id: users(:two).id, locked_at: Time.current)
    sign_in_as users(:one)
    visit tool_docs_document_path(document.tool, document)
    wait_for_stimulus "document-viewer"

    assert_selector "[data-document-viewer-target='lockStatus']", text: "#{users(:two).name} is editing"
    assert_edit_open(document)

    edit_link(document).click
    assert_current_path edit_tool_docs_document_path(document.tool, document)
  end

  test "someone opening the editor while you read doesn't take your Edit button away" do
    document = docs_documents(:shared_notes)
    sign_in_as users(:one)
    visit tool_docs_document_path(document.tool, document)
    wait_for_stimulus "document-viewer"
    assert_no_selector "[data-document-viewer-target='lockStatus']"

    # Said again until the page's subscription is there to hear it
    assert_eventually do
      DocumentChannel.broadcast_to(document, { type: "locked", user_name: users(:two).name, user_id: users(:two).id })
      page.has_selector?("[data-document-viewer-target='lockStatus']", text: "#{users(:two).name} is editing", wait: 0.5)
    end
    assert_edit_open(document)

    # Your own editor, in another tab, is nobody else
    DocumentChannel.broadcast_to(document, { type: "locked", user_name: users(:one).name, user_id: users(:one).id })
    assert_no_selector "[data-document-viewer-target='lockStatus']"
    assert_edit_open(document)
  end

  test "your own editor open elsewhere isn't someone else editing" do
    document = docs_documents(:shared_notes)
    document.update_columns(locked_by_id: users(:one).id, locked_at: Time.current)
    sign_in_as users(:one)
    visit tool_docs_document_path(document.tool, document)
    wait_for_stimulus "document-viewer"

    assert_no_text "is editing"
    assert_edit_open(document)
  end

  private

  def edit_link(document)
    find("a[href='#{edit_tool_docs_document_path(document.tool, document)}']")
  end

  def assert_edit_open(document)
    link = edit_link(document)
    assert_nil link[:"aria-disabled"]
    assert_not_includes link[:class], "pointer-events-none"
  end

  def assert_eventually(timeout: 5)
    deadline = Time.current + timeout
    sleep 0.1 until yield || Time.current > deadline
    assert yield, "condition wasn't met within #{timeout} seconds"
  end
end
