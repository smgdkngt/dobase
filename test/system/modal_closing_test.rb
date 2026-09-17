# frozen_string_literal: true

require "application_system_test_case"

class ModalClosingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "creating an API token keeps the profile modal open so the one-time token can be copied" do
    visit tools_path
    wait_for_turbo
    find("button.sidebar-user-btn").click
    within("#sidebar-user-menu") { click_on "Profile" }
    assert_selector "#profile-modal[open]", wait: 5

    within("#profile-modal") do
      click_on "API"
      find("input[name='name']").set("CLI")
      click_on "Create token"
    end

    assert_db_change(-> { @user.access_tokens.exists?(name: "CLI") })
    assert_selector "#profile-modal[open]"
    assert_selector "#profile-modal", text: "Copy your new token now"
  end

  test "inviting a collaborator keeps the edit-tool modal open" do
    tool = tools(:my_files)
    visit tool_files_path(tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    # The settings gear only shows on hover
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{tool.id}']", visible: :all).execute_script("this.click()")
    assert_selector "#edit-tool-modal[open]", wait: 5
    wait_for_stimulus "tabs", "#edit-tool-modal [data-controller~='tabs']"

    within("#edit-tool-modal") do
      click_on "Collaborators"
      find("input[name='email']", wait: 5).set("friend@example.com")
      click_on "Add"
    end

    assert_db_change(-> { tool.invitations.exists?(email: "friend@example.com") })
    assert_selector "#edit-tool-modal[open]"
    assert_selector "#edit-tool-modal", text: "friend@example.com"
  end

  test "saving the profile form (turbo_frame _top) still closes the modal" do
    visit tools_path
    wait_for_turbo
    find("button.sidebar-user-btn").click
    within("#sidebar-user-menu") { click_on "Profile" }
    assert_selector "#profile-modal[open]", wait: 5

    within("#profile-modal") { click_on "Save changes" }

    assert_no_selector "#profile-modal[open]", wait: 5
  end
end
