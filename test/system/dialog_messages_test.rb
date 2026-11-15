# frozen_string_literal: true

require "application_system_test_case"

# What a dialog says when something it sent didn't go, or did: in the dialog, with the
# workspace around it left as it was, and a message for the start page on the page
# that is finally drawn.
class DialogMessagesTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @board = tools(:project_board)
    sign_in_as users(:one)
    # As it is outside the tests: a wide window works in the workspace
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 1
  end

  test "a tool added without a type says so in the dialog, and the workspace stays" do
    page.execute_script("window.stillTheSamePage = true")
    open_menu
    find(".sidebar-logo-btn", match: :first).click
    click_on "Add Tool"

    within "dialog#new-tool-modal[open]" do
      # The browser asks for a type first; this is what the server says when it gets none
      page.execute_script("document.querySelectorAll('#new-tool-modal input[type=radio]').forEach((radio) => radio.required = false)")
      fill_in "Name", with: "Groceries"
      click_on "Create"

      assert_selector ".flash-error", text: "Tool type must exist"
      assert_field "Name", with: "Groceries"

      find("label", text: "Todos").click
      click_on "Create"
    end

    assert_selector ".workspace-tile:not([hidden], [data-leaving])", count: 2
    assert_current_path workspace_path
    assert page.evaluate_script("window.stillTheSamePage"), "the workspace was loaded again"
  end

  test "a wrong current password is said in the profile dialog, and the workspace stays" do
    page.execute_script("window.stillTheSamePage = true")
    open_profile_on "security"

    within "dialog#profile-modal[open]" do
      fill_in "Current password", with: "not-my-password"
      fill_in "New password", with: "brand-new-secret"
      fill_in "Confirm password", with: "brand-new-secret"
      click_on "Update password"

      assert_selector ".flash", text: "Your current password is incorrect."
      assert_selector "[data-tabs-target='tab'][data-tab='security'].active"
    end

    assert_selector ".workspace-bar"
    assert_current_path workspace_path
    assert page.evaluate_script("window.stillTheSamePage"), "the workspace was loaded again"
  end

  test "a new password that is too short is said on the tab it was typed in" do
    open_profile_on "security"

    within "dialog#profile-modal[open]" do
      fill_in "Current password", with: "password"
      fill_in "New password", with: "short"
      fill_in "Confirm password", with: "short"
      click_on "Update password"

      assert_selector ".flash-error", text: "too short"
      assert_selector "[data-tabs-target='tab'][data-tab='security'].active"
    end
    assert_selector ".workspace-bar"
    assert users(:one).reload.authenticate("password")
  end

  test "an invitation says how it went in the settings, and keeps a refused address" do
    open_menu
    find(".sidebar-tool-menu-btn[data-tool-id='#{@board.id}']", visible: :all).click

    within "dialog#edit-tool-modal[open]" do
      click_on "Collaborators"
      find("input[name='email']").set(users(:one).email_address)
      click_on "Add"

      assert_selector ".flash", text: "You cannot invite yourself."
      assert_equal users(:one).email_address, find("input[name='email']").value
      assert_selector "[data-tabs-target='tab'][data-tab='collaborators'].active"

      find("input[name='email']").set("friend@example.com")
      click_on "Add"

      assert_selector ".flash", text: "Invitation sent to friend@example.com."
      assert_selector "[data-tab='collaborators']", text: "friend@example.com"
      assert_equal "", find("input[name='email']").value
    end
    assert_selector ".workspace-bar"
  end

  test "a deleted tool is said in the workspace" do
    tool = Tool.create!(name: "Scratch", tool_type: tool_types(:docs), owner: users(:one))
    visit workspace_path
    wait_for_stimulus "workspace"

    open_menu
    find(".sidebar-tool-menu-btn[data-tool-id='#{tool.id}']", visible: :all).click
    within "dialog#edit-tool-modal[open]" do
      find("a, button", text: "Delete", match: :first).click
    end
    # The confirmation dialog opens with an animation, and on a busy machine a click
    # during it can come to nothing: pressed again until the dialog has gone
    confirm = "dialog#turbo-confirm-dialog[open] button[value='confirm']"
    3.times do
      find(confirm).click
      break if has_no_selector?(confirm, wait: 3)
    end

    assert_selector ".flash-toast .flash", text: "Scratch deleted successfully."
    assert_selector ".workspace-bar"
    assert_not Tool.exists?(tool.id)
  end

  private

  def open_menu
    find(".workspace-bar-btn[aria-label='Menu']").click
    assert_selector ".sidebar.open"
  end

  def open_profile_on(tab)
    find(".workspace-bar-btn[popovertarget='sidebar-user-menu']").click
    click_on "Profile"
    within "dialog#profile-modal[open]" do
      find("[data-tabs-target='tab'][data-tab='#{tab}']").click
    end
  end
end

# The same dialogs over a page with the sidebar, as a narrow window has them, and a
# message on a tool's page that a wide window leaves for the workspace
class DialogMessagesOnAPageTest < ApplicationSystemTestCase
  test "a tool added without a type says so in the dialog, over a page with the sidebar" do
    sign_in_as users(:one)
    visit tool_board_path(tools(:project_board))
    page.execute_script("window.stillTheSamePage = true")
    find(".sidebar-logo-btn", match: :first).click
    click_on "Add Tool"

    within "dialog#new-tool-modal[open]" do
      page.execute_script("document.querySelectorAll('#new-tool-modal input[type=radio]').forEach((radio) => radio.required = false)")
      fill_in "Name", with: "Groceries"
      click_on "Create"

      assert_selector ".flash-error", text: "Tool type must exist"
    end
    assert_selector "h1", text: tools(:project_board).name
    assert page.evaluate_script("window.stillTheSamePage"), "the page was loaded again"
  end

  test "a wrong current password is said in the profile dialog, over a page with the sidebar" do
    sign_in_as users(:one)
    visit tool_board_path(tools(:project_board))
    find("button.sidebar-user-btn").click
    within("#sidebar-user-menu") { click_on "Profile" }

    within "dialog#profile-modal[open]" do
      find("[data-tabs-target='tab'][data-tab='security']").click
      fill_in "Current password", with: "not-my-password"
      fill_in "New password", with: "brand-new-secret"
      fill_in "Confirm password", with: "brand-new-secret"
      click_on "Update password"

      assert_selector ".flash", text: "Your current password is incorrect."
      assert_selector "[data-tabs-target='tab'][data-tab='security'].active"
    end
    assert_selector "h1", text: tools(:project_board).name
  end

  test "an invitation accepted is said in the workspace a wide window goes to" do
    newcomer = User.create!(first_name: "New", last_name: "Comer", email_address: "newcomer@example.com", password: "password")
    invitation = tools(:shared_board).invitations.create!(email: newcomer.email_address, invited_by: users(:one))
    sign_in_as newcomer
    page.driver.browser.manage.delete_cookie("workspace")

    visit invitation_acceptance_path(token: invitation.token)
    click_on "Accept Invitation"

    assert_selector ".flash-toast .flash", text: "You are now a collaborator on #{tools(:shared_board).name}!"
    assert_selector "body[data-workspace]"
  end
end
