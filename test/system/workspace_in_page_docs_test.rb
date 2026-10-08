# frozen_string_literal: true

require "application_system_test_case"

# Documents as a tile in the workspace's own page (workspace_controller.js#inThisPage).
# What every such tile does is in workspace_in_page_test.rb; this is what documents
# have of their own: pages inside the tile, and an editor that keeps what is typed.
class WorkspaceInPageDocsTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  DOCS = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @tool = tools(:my_docs)
    @document = docs_documents(:meeting_notes)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@tool))
    wait_for_stimulus "workspace"
    assert_selector "#{DOCS} .tile-page h1", text: @tool.name
    within(".workspace-hint") { click_on "Got it" }
  end

  test "a document opens in the tile, and the arrow back is the list again" do
    within(DOCS) { click_on @document.title, match: :first }

    assert_selector "#{DOCS} .document-view", text: @document.content.to_plain_text.split.first
    assert_selector "#{DOCS}[src*='/documents/#{@document.id}']"
    assert_current_path workspace_path
    assert_equal 0, page.evaluate_script("window.frames.length")

    within(DOCS) { find("a[aria-label='Back']").click }
    assert_selector "#{DOCS} .tile-page h1", text: @tool.name
  end

  test "the workspace remembers the document the tile was on" do
    within(DOCS) { click_on @document.title, match: :first }
    assert_selector "#{DOCS} .document-view"
    assert_db_change -> { WorkspaceLayout.find_by(user: users(:one))&.state.to_json.to_s.include?("/documents/#{@document.id}") }

    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{DOCS} .document-view", text: @document.content.to_plain_text.split.first
  end

  test "what is written in the tile is saved, by itself and when the tile is closed" do
    within(DOCS) { click_on @document.title, match: :first }
    within(DOCS) { click_on "Edit" }
    wait_for_stimulus "document-editor"
    editor.send_keys(:end, " Written in a tile")
    assert_selector "#{DOCS} [data-document-editor-target='saveIndicator']", text: "Saved", wait: 10
    assert_includes @document.reload.content.to_plain_text, "Written in a tile"

    # Closed well within the two-second autosave delay
    editor.send_keys(:end, " and at the last second")
    find(DOCS).find(:xpath, "..").find("button[title^='Close this tile']", visible: :all).execute_script("this.click()")
    assert_no_selector DOCS
    assert_db_change -> { @document.reload.content.to_plain_text.include?("and at the last second") }
  end

  test "a new document is made with its key and opens in the tile to be written" do
    find(DOCS).click
    find("#{DOCS} .tile-page").send_keys("n")

    assert_selector "#{DOCS} [data-controller~='document-editor']"
    assert_selector "#{DOCS}[src*='/edit']"
    assert_current_path workspace_path
    assert_equal 1, all(DOCS).size
  end

  test "a document is deleted from the tile, and the list is what is left" do
    within(DOCS) { click_on @document.title, match: :first }
    within(DOCS) { find("a[title='Delete document'], button[title='Delete document']").click }
    find("dialog#turbo-confirm-dialog[open] button[value='confirm']").click

    assert_selector "#{DOCS} .tile-page h1", text: @tool.name
    assert_no_selector "#{DOCS} [data-document-id='#{@document.id}']"
    assert_not Docs::Document.exists?(@document.id)
    assert_current_path workspace_path
  end

  test "grid and list are switched in the tile, and the window keeps its address" do
    within(DOCS) { find("a[aria-label='List view']").click }
    assert_selector "#{DOCS} a[aria-label='List view'][aria-current='true']"
    assert_current_path workspace_path

    within(DOCS) { find("a[aria-label='Grid view']").click }
    assert_selector "#{DOCS} a[aria-label='Grid view'][aria-current='true']"
    assert_current_path workspace_path
  end

  test "a narrow tile has fewer documents beside each other than a wide one" do
    4.times { |number| @tool.documents.create!(title: "Note #{number}", created_by: users(:one), updated_by: users(:one)) }
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{DOCS} [data-document-id]", minimum: 6
    wide = columns_of_documents
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(tools(:my_room)))
    assert_selector "#{TILE} > iframe"

    assert_operator columns_of_documents, :<, wide
  end

  private

  def editor
    find("#{DOCS} [data-document-editor-target='editor']:not([inert]) .ProseMirror")
  end

  # How many documents stand in the first row of the grid
  def columns_of_documents
    page.document.synchronize do
      tops = page.evaluate_script("Array.from(document.querySelectorAll(#{"#{DOCS} [data-document-id]".to_json})).map((card) => Math.round(card.getBoundingClientRect().top))")
      raise Capybara::ExpectationNotMet, "No documents drawn yet" if tops.empty?

      tops.count(tops.first)
    end
  end
end
