# frozen_string_literal: true

require "application_system_test_case"

class FilesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
    sign_in_as(@user)
  end

  test "viewing files shows folders and files" do
    visit tool_files_path(@tool)

    assert_text "Documents"
    assert_text "Photos"
    assert_text "readme.txt"
  end

  test "switching between grid and list view" do
    visit tool_files_path(@tool)

    assert_text "Documents"
    assert_text "readme.txt"

    find("a[href*='view=list']").click

    assert_text "Documents"
    assert_text "readme.txt"

    find("a[href*='view=grid']").click

    assert_text "Documents"
    assert_text "readme.txt"
  end

  test "creating a new folder via dialog" do
    visit tool_files_path(@tool)

    click_on "New Folder"

    # Fill in and submit using JS to avoid native dialog interaction issues
    page.execute_script(<<~JS)
      const input = document.querySelector('#folder_name');
      const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      nativeInputValueSetter.call(input, 'Projects');
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.form.requestSubmit();
    JS

    assert_text "Projects"
    assert ::Files::Folder.exists?(name: "Projects")
  end

  test "navigating into folder shows breadcrumbs and contents" do
    visit tool_files_path(@tool)

    wait_for_turbo
    folder = find("[data-item-type='folder'][data-item-id='#{file_folders(:documents).id}']")
    folder.double_click
    # Double-click triggers Turbo.visit via Stimulus — wait for navigation
    assert_selector "nav", text: "Documents", wait: 10
    assert_text "Subfolder"
    assert_text "report.pdf"
  end

  test "creating a share link for a file" do
    visit tool_files_path(@tool, folder_id: file_folders(:documents).id)

    file = file_items(:report)
    assert_text "report.pdf"

    open_context_menu(file)
    click_on "Share"

    within "dialog[open]" do
      assert_selector "button", text: "Create Link"
      click_on "Create Link"
      assert_selector "button", text: "Copy", wait: 5
    end

    assert file.reload.share.present?, "Expected share to be created for file"
  end

  test "removing a share link" do
    visit tool_files_path(@tool)

    file = file_items(:readme)
    assert file.share.present?, "Fixture should have an existing share"
    assert_text "readme.txt"

    open_context_menu(file)
    click_on "Share"

    within "dialog[open]" do
      click_on "Remove Share"
    end

    # Custom turbo confirm dialog
    within "dialog#turbo-confirm-dialog" do
      find("button[value='confirm']").click
    end

    sleep 0.5
    assert_nil file.reload.share, "Expected share to be removed"
  end

  test "downloading a selection of a folder and a file as one zip" do
    file_items(:readme).file.attach(io: StringIO.new("read me first"), filename: "readme.txt", content_type: "text/plain")
    file_items(:report).file.attach(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")

    visit tool_files_path(@tool)
    wait_for_turbo

    Dir.mktmpdir do |downloads|
      page.driver.browser.download_path = downloads

      find("[data-item-type='folder'][data-item-id='#{file_folders(:documents).id}']").click
      find("[data-item-type='file'][data-item-id='#{file_items(:readme).id}']").click(:meta)
      assert_text "2 selected"

      click_on "Download"

      zip = wait_for_download(File.join(downloads, "My Files.zip"))
      entries = Zip::File.open(zip) { |archive| archive.entries.to_h { |entry| [ entry.name, entry.get_input_stream.read ] } }
      assert_equal({ "Documents/report.pdf" => "quarterly numbers", "readme.txt" => "read me first" }, entries)
    end
  end

  private

  # Chrome saves to a .crdownload file and renames it once the download is done.
  def wait_for_download(path, timeout: 10)
    deadline = Time.now + timeout
    sleep 0.2 until File.exist?(path) || Time.now > deadline
    assert File.exist?(path), "Expected #{File.basename(path)} to be downloaded"
    path
  end

  def open_context_menu(file)
    item = find("[data-item-type='file'][data-item-id='#{file.id}']")
    # Make the menu button visible (hover CSS unreliable in headless Chrome)
    menu_btn = item.find("button[data-action*='file-context-menu#showFromButton']", visible: :all)
    page.execute_script("arguments[0].style.opacity = '1'; arguments[0].style.pointerEvents = 'auto'", menu_btn.native)
    sleep 0.1
    menu_btn.click
    # Retry if the menu didn't appear
    unless page.has_selector?("[data-file-context-menu-target='menu']:not(.hidden)", wait: 2)
      menu_btn.click
    end
    find("[data-file-context-menu-target='menu']", visible: true)
  end

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end
