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

  test "a tool dropped at the top of a sidebar group stays there, however slowly the move is saved" do
    group = users(:one).sidebar_groups.create!(name: "Work", position: 0)
    group.memberships.create!(tool: tools(:my_files), position: 0)
    visit tool_board_path(tools(:project_board))
    wait_for_turbo
    wait_for_stimulus "sidebar"
    wait_for_stimulus "sortable", "[data-sidebar-target='groupContent']"

    # What a drop of My Mail above My Files does, with the request that moves it held up
    page.execute_script(<<~JS, tools(:my_mail).id, group.id)
      const original = window.fetch
      window.fetch = (url, options = {}) => {
        const held = String(url).includes("/memberships") ? 500 : 0
        return new Promise(resolve => setTimeout(resolve, held)).then(() => original(url, options))
      }

      const from = document.querySelector("[data-controller~='sortable'][data-group-id='ungrouped']")
      const to = document.querySelector(`[data-sidebar-target='groupContent'][data-group-id='${arguments[1]}']`)
      const item = from.querySelector(`[data-sort-id='${arguments[0]}']`)
      to.prepend(item)
      window.Stimulus.getControllerForElementAndIdentifier(to, "sortable").onEnd({ from, to, item })
    JS

    assert_db_change(-> { group.memberships.reload.size == 2 })
    sleep 0.5
    assert_equal [ tools(:my_mail), tools(:my_files) ], group.memberships.reload.map(&:tool)
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
