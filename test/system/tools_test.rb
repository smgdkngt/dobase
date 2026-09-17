# frozen_string_literal: true

require "application_system_test_case"

class ToolsTest < ApplicationSystemTestCase
  setup do
    @tool = tools(:my_files)
    sign_in_as users(:one)
  end

  test "deleting a tool asks with a Delete button" do
    open_tool_settings

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

  test "cancelling keeps the tool, even after an earlier confirmation on the page" do
    open_tool_settings
    # What an earlier Confirm leaves on the dialog, which stays in the page across morph refreshes
    page.execute_script("document.getElementById('turbo-confirm-dialog').returnValue = 'confirm'")

    within "dialog#edit-tool-modal[open]" do
      click_on "Delete"
    end
    within "dialog#turbo-confirm-dialog" do
      click_on "Cancel"
    end

    assert_not page.has_current_path?(root_path, wait: 2)
    assert Tool.exists?(@tool.id)
  end

  private

  def open_tool_settings
    visit tool_path(@tool)
    wait_for_turbo
    wait_for_stimulus "sidebar"
    # The settings gear only shows on hover
    find("[data-action~='click->sidebar#editTool'][data-tool-id='#{@tool.id}']", visible: :all).execute_script("this.click()")
  end
end
