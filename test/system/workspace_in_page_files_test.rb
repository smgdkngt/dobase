# frozen_string_literal: true

require "application_system_test_case"

# Files as a tile in the workspace's own page (workspace_controller.js#inThisPage).
# What every such tile does is in workspace_in_page_test.rb; this is what files have
# of their own: folders gone into inside the tile, a menu where the pointer is, and
# uploads that draw the tile again.
class WorkspaceInPageFilesTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  FILES = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @tool = tools(:my_files)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path("in-page": "todos,boards,chat,docs,calendar,files", open: tool_path(@tool))
    wait_for_stimulus "workspace"
    assert_selector "#{FILES} .tile-page h1", text: @tool.name
    wait_for_stimulus "files"
    within(".workspace-hint") { click_on "Got it" }
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('dobase:workspace:in-page') } catch (error) {}")
  end

  test "a folder is gone into in the tile, and its path leads back" do
    folder = file_folders(:documents)
    find("#{FILES} #{item(folder)}").double_click

    assert_selector "#{FILES} nav", text: "Documents"
    assert_selector "#{FILES}[src*='folder_id=#{folder.id}']"
    within(FILES) { assert_text "report.pdf" }
    assert_current_path workspace_path
    assert_equal 0, page.evaluate_script("window.frames.length")

    find("#{FILES} nav a[href='#{tool_files_path(@tool)}']").click
    assert_selector "#{FILES} #{item(folder)}"
  end

  test "a file opens in the tile and the arrow back is its folder" do
    find("#{FILES} #{item(file_items(:readme))}").double_click

    assert_selector "#{FILES} h1", text: "readme.txt"
    assert_current_path workspace_path

    within(FILES) { find("a[data-arrow-keys-target='back']").click }
    assert_selector "#{FILES} #{item(file_items(:readme))}"
  end

  test "a folder is made from the tile, and shows in it" do
    within(FILES) { click_on "New Folder" }
    within("dialog[aria-labelledby='files-folder-title-#{@tool.id}'][open]") do
      fill_in "Folder name", with: "Projects"
      click_on "Create"
    end

    assert_selector "#{FILES} [data-item-type='folder']", text: "Projects"
    assert ::Files::Folder.exists?(name: "Projects")
    assert_current_path workspace_path
    assert_selector FILES, count: 1
  end

  test "the menu of a file opens where the pointer is, and deletes the file" do
    readme = file_items(:readme)
    target = find("#{FILES} #{item(readme)}")
    target.right_click

    menu = find("[data-file-context-menu-target='menu']")
    at = page.evaluate_script(<<~JS)
      (() => {
        const menu = document.querySelector("[data-file-context-menu-target='menu']").getBoundingClientRect()
        const file = document.querySelector(#{"#{FILES} #{item(readme)}".to_json}).getBoundingClientRect()
        return { left: menu.left, top: menu.top, fileLeft: file.left, fileRight: file.right, fileTop: file.top, fileBottom: file.bottom }
      })()
    JS
    # The click was in the middle of the file: the menu's corner is there, not an eighth off
    assert_in_delta (at["fileLeft"] + at["fileRight"]) / 2, at["left"], 6
    assert_in_delta (at["fileTop"] + at["fileBottom"]) / 2, at["top"], 6

    within(menu) { click_on "Delete" }
    within("dialog#turbo-confirm-dialog[open]") { click_on "Delete" }

    assert_no_selector "#{FILES} #{item(readme)}"
    assert_not ::Files::Item.exists?(readme.id)
    assert_current_path workspace_path
  end

  test "a file is uploaded, and the tile shows it" do
    wait_for_stimulus "file-upload"
    picture = Rails.root.join("test/fixtures/files/sample.png")

    find("#{FILES} [data-file-upload-target='input']", visible: :all).attach_file(picture, make_visible: true)

    assert_db_change(-> { @tool.file_items.where(name: "sample.png").count == 1 })
    assert_selector "#{FILES} [aria-label='View sample.png']", visible: :all
    assert_current_path workspace_path
  end

  test "grid and list are switched in the tile" do
    within(FILES) { find("a[aria-label='List view']").click }
    assert_selector "#{FILES} a[aria-label='List view'][aria-current='true']"
    assert_current_path workspace_path
  end

  test "the arrows go from file to file and never out of the files" do
    find("#{FILES} .tile-page h1").click
    %i[arrow_down arrow_right arrow_right arrow_down arrow_left arrow_up arrow_up arrow_up].each do |arrow|
      page.send_keys(arrow)
      inside = page.evaluate_script("Boolean(document.activeElement.closest('turbo-frame.tile-frame'))")
      assert inside, "#{arrow} took the keyboard out of the files"
    end
  end

  private

  def item(record)
    type = record.is_a?(::Files::Folder) ? "folder" : "file"
    "[data-item-type='#{type}'][data-item-id='#{record.id}']"
  end
end
