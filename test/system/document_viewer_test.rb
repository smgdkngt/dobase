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
end
