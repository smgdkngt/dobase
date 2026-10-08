# frozen_string_literal: true

require "application_system_test_case"

# Everything on a page that can be pressed can be got to with the arrow keys alone
# (arrow_keys_controller.js): the items a view marks, and whatever else takes the
# keyboard there, a filter, the buttons of a top bar, what a detail view or a dialog has.
#
# The page is walked from where the keyboard starts: every arrow from every place
# that was reached, until nothing new turns up. What was never reached is the failure.
class ArrowKeysReachTest < ApplicationSystemTestCase
  WALK = <<~JS
    const done = arguments[arguments.length - 1]
    const TAKES = "a[href], button, input:not([type='hidden']), select, textarea, summary, [role='button'], [tabindex]:not([tabindex='-1']), [contenteditable='true']"
    const root = document.querySelector(arguments[0] || "dialog[open]") || document.querySelector("main")
    const inDialog = !root.matches("main")
    const shown = (element) => element.getClientRects().length > 0 && !element.closest("[inert]")
    const pressable = (element) => {
      if (element.disabled || !(element.tabIndex >= 0 || element.isContentEditable) || !shown(element)) return false
      const box = element.getBoundingClientRect()
      return box.width > 4 && box.height > 4 && getComputedStyle(element).pointerEvents !== "none"
    }
    const named = (element) => (element.tagName.toLowerCase() + " " + (element.getAttribute("aria-label") || element.title || element.placeholder || element.textContent || element.name || "").trim().replace(/\\s+/g, " ").slice(0, 40)).trim()
    const items = [ ...root.querySelectorAll("[data-arrow-keys-target~='item']") ].filter(shown)
    // What an item has of its own (a file's menu button) is reached where the items
    // run out on that side, which in a grid is not from every one of them
    const wanted = [ ...new Set([ ...root.querySelectorAll(TAKES) ].filter((element) => pressable(element) && !items.some((item) => item !== element && item.contains(element))).concat(items)) ]

    // Nothing may happen but the keyboard going somewhere
    const stop = (event) => { event.preventDefault(); event.stopImmediatePropagation() }
    document.addEventListener("click", stop, true)
    window.addEventListener("arrow-keys:edge", stop, true)
    window.addEventListener("arrow-keys:went", (event) => event.stopImmediatePropagation(), true)

    const press = (key) => (document.activeElement || document.body).dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, composed: true }))
    const start = inDialog && root.contains(document.activeElement) ? document.activeElement : null
    const reached = new Set(start ? [ start ] : [])
    const from = [ start ]
    for (let turns = 0; from.length > 0 && turns < 500; turns++) {
      const place = from.shift()
      for (const key of [ "ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp" ]) {
        if (place) { place.focus({ preventScroll: true }); place.scrollIntoView({ block: "nearest" }) } else if (inDialog) root.focus(); else document.activeElement?.blur?.()
        const still = document.activeElement
        let now = still
        // (what lies out of sight is come nearer to a step at a time)
        for (let presses = 0; presses < 60 && now === still; presses++) { press(key); now = document.activeElement }
        if (now && now !== document.body && root.contains(now) && !reached.has(now)) { reached.add(now); from.push(now) }
      }
    }
    done({ wanted: wanted.length, missed: wanted.filter((element) => !reached.has(element)).map(named) })
  JS

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "a board, its top bar and its columns' own buttons" do
    visit tool_board_path(tools(:project_board))
    assert_everything_in_reach minimum: 8
  end

  test "a card's details: its fields, its buttons, its comment box" do
    visit tool_board_path(tools(:project_board), card: cards(:first_task).id)
    assert_selector "dialog#card-detail-modal[open] h2", text: "First task"
    assert_everything_in_reach minimum: 5
  end

  test "todos, with their lists' own buttons" do
    visit tool_todo_path(tools(:my_todos))
    assert_everything_in_reach minimum: 6
  end

  test "the documents, and a document that is open" do
    visit tool_docs_path(tools(:my_docs))
    assert_everything_in_reach minimum: 3

    visit tool_docs_document_path(tools(:my_docs), docs_documents(:meeting_notes))
    assert_everything_in_reach minimum: 2
  end

  test "files and folders, with the buttons above them" do
    visit tool_files_path(tools(:my_files))
    assert_everything_in_reach minimum: 4
  end

  test "the calendar: its events and the buttons that go through the weeks" do
    visit tool_calendar_path(tools(:my_calendar))
    assert_everything_in_reach minimum: 5
  end

  test "mail: the conversations, the buttons above them, and a conversation that is open" do
    visit tool_mails_path(tools(:my_mail))
    assert_everything_in_reach minimum: 5

    visit tool_mail_path(tools(:my_mail), mails_messages(:inbox_unread))
    assert_selector ".mail-detail-header"
    assert_everything_in_reach minimum: 8
  end

  test "a room before the call: the microphone, the camera, the way in" do
    visit tool_room_path(tools(:my_room))
    assert_everything_in_reach minimum: 2
  end

  test "the shortcuts, which are a dialog over whatever page" do
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "keyboard-shortcuts"
    find("body").send_keys("?")
    assert_selector "dialog[open]", text: "Keyboard shortcuts"
    assert_everything_in_reach minimum: 1
  end

  test "the bar of the workspace: the menu, the desktops, the bell, yourself" do
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector ".workspace-tile > :is(iframe, .tile-frame)"
    find(".workspace-bar-btn[aria-label='Menu']").send_keys(:tab)

    assert_everything_in_reach minimum: 4, within: ".workspace-bar"
  end

  test "the menu of the workspace: the search, the tools, their settings, the buttons" do
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path
    wait_for_stimulus "workspace"
    find(".workspace-bar-btn[aria-label='Menu']").click
    assert_selector ".sidebar.open input:focus"

    assert_everything_in_reach minimum: 10, within: ".sidebar.open"
  end

  private

  def assert_everything_in_reach(minimum:, within: nil)
    wait_for_turbo
    wait_for_stimulus "arrow-keys"
    page.driver.browser.manage.timeouts.script_timeout = 60
    walked = page.driver.browser.execute_async_script(WALK, within)

    assert_operator walked["wanted"], :>=, minimum, "there is less on the page than the test thinks"
    assert_empty walked["missed"], "the arrow keys never got to: #{walked["missed"].join("; ")}"
  end
end
