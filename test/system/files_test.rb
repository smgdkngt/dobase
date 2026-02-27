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

    find("[data-item-type='folder'][data-item-id='#{file_folders(:documents).id}']").double_click

    assert_selector "nav", text: "Documents"
    assert_text "Subfolder"
    assert_text "report.pdf"
  end

  test "creating a share link for a file" do
    visit tool_files_path(@tool, folder_id: file_folders(:documents).id)

    file = file_items(:report)
    assert_text "report.pdf"

    # Hover over file and click three-dots menu button
    item = find("[data-item-type='file'][data-item-id='#{file.id}']")
    item.hover
    item.find("button[data-action*='file-context-menu#showFromButton']").click

    find("[data-file-context-menu-target='menu']", visible: true)
    within "[data-file-context-menu-target='menu']" do
      click_on "Share"
    end

    within "dialog[open]" do
      assert_selector "button", text: "Create Link"
      click_on "Create Link"
      assert_selector "button", text: "Copy"
    end

    assert file.reload.share.present?, "Expected share to be created for file"
  end

  test "removing a share link" do
    visit tool_files_path(@tool)

    file = file_items(:readme)
    assert file.share.present?, "Fixture should have an existing share"
    assert_text "readme.txt"

    # Hover over file and click three-dots menu button
    item = find("[data-item-type='file'][data-item-id='#{file.id}']")
    item.hover
    item.find("button[data-action*='file-context-menu#showFromButton']").click

    find("[data-file-context-menu-target='menu']", visible: true)
    within "[data-file-context-menu-target='menu']" do
      click_on "Share"
    end

    within "dialog[open]" do
      assert_selector "button", text: "Remove Share"
      accept_confirm "Remove public access?" do
        click_on "Remove Share"
      end
    end

    sleep 0.5
    assert_nil file.reload.share, "Expected share to be removed"
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign In"
    assert_selector ".sidebar", wait: 5
  end
end
