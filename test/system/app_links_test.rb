# frozen_string_literal: true

require "application_system_test_case"

# /app/… hands a page to the installed app (AppLinksController). Headless Chrome
# hands a link to no program, and holds the page as a real one does while it asks
# whether it may: a click on the page doesn't get through then.
class AppLinksTest < ApplicationSystemTestCase
  setup do
    sign_in_as(users(:one))
  end

  test "in a browser the tab stays behind, with a way to go on here" do
    board = tool_board_path(tools(:project_board))
    visit "/app#{board}"

    assert_text "Opening in the #{app_name} app"
    assert_current_path "/app#{board}"
    assert_selector "a[href='web+dobase:/#{board}']", text: "Open in the app"
    assert_selector "a[href='#{board}']", text: "Open here instead"
  end

  test "a window that is the app already goes to the page" do
    page.execute_script("sessionStorage.setItem('app-window', '1')")
    visit "/app#{tool_board_path(tools(:project_board))}?from=chat"

    assert_current_path tool_board_path(tools(:project_board), from: "chat")
    assert_selector ".sidebar"
  end

  # As its preload.js does: before the page's own scripts
  test "the app from `dobase app install` goes to the page" do
    preload = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      new MutationObserver((changes, observer) => {
        if (!document.documentElement) return
        document.documentElement.dataset.appWindow = ""
        observer.disconnect()
      }).observe(document, { childList: true })
    JS
    visit "/app#{tool_board_path(tools(:project_board))}"

    assert_current_path tool_board_path(tools(:project_board))
  ensure
    # The browser outlives the test: the next one is a browser tab again
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: preload["identifier"]) if preload
  end

  private
    def app_name
      Rails.application.config.x.app.name
    end
end
