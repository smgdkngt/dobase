# frozen_string_literal: true

require "application_system_test_case"

class ToolsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_files)
    sign_in_as users(:one)
  end

  test "deleting a tool asks with a Delete button" do
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    # The settings gear only shows on hover
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")

    within "dialog#edit-tool-modal[open]" do
      click_on "Delete"
    end

    within "dialog#turbo-confirm-dialog" do
      assert_text "Are you sure you want to delete this tool?"
      assert_selector "button[value='confirm']", text: "Delete"
      click_on "Cancel"
    end

    assert_no_selector "dialog#turbo-confirm-dialog[open]"
    assert Tool.exists?(@tool.id)
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
