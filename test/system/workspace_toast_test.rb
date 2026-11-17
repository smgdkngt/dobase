# frozen_string_literal: true

require "application_system_test_case"

# A toast in the workspace lies over the page around the tiles, never over what can be
# pressed in a tile. It sat at the top right whenever a chat was open in any tile (the rule
# for a chat's own page, whose composer takes the bottom), over the mailbox's buttons
# beside it: refresh, settings, Compose, close (2026-11-17).
class WorkspaceToastTest < ApplicationSystemTestCase
  TILE = ".workspace-tile:not([hidden], [data-leaving])"

  setup do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.assign_attributes(name: "Chat", icon: "message-circle", enabled: true) }
    @chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: users(:one))
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_path(@chat))
    wait_for_stimulus "workspace"
    assert_selector "#{TILE} .tile-page h1", text: "Team Chat"
    wait_for_stimulus "chat"
    within(".workspace-hint") { click_on "Got it" }
  end

  test "the Undo after trashing a mail covers nothing in the tiles, beside a chat too" do
    page.execute_script("window.dispatchEvent(new CustomEvent('workspace:open', { detail: { url: arguments[0] } }))", tool_path(tools(:my_mail)))
    assert_selector "#{TILE} .mail-list-item", text: "Welcome to Dobase"
    find("#{TILE} .mail-list-item", text: "Welcome to Dobase").click
    assert_selector "#{TILE} .mail-detail-header h1", text: "Welcome to Dobase"
    find("#{TILE} .mail-detail-header h1").click
    page.send_keys("#")

    assert_selector "#flash .flash", text: "trash"
    assert_selector "#flash .flash button, #flash .flash form", minimum: 1
    page.save_screenshot(ENV["TOAST_SHOT"]) if ENV["TOAST_SHOT"]
    covered = page.evaluate_script(<<~JS)
      (() => {
        const toast = document.querySelector("#flash .flash").getBoundingClientRect()
        return [ ...document.querySelectorAll("#workspace-tiles :is(a, button, input, textarea, [contenteditable], rhino-editor, [role=button])") ]
          .filter((element) => element.checkVisibility())
          .filter((element) => {
            const box = element.getBoundingClientRect()
            return box.width > 0 && box.left < toast.right && box.right > toast.left && box.top < toast.bottom && box.bottom > toast.top
          })
          .map((element) => element.title || element.getAttribute("aria-label") || element.textContent.trim().slice(0, 30) || element.tagName)
      })()
    JS
    assert_empty covered, "the toast lies over #{covered.inspect}"
  end
end
