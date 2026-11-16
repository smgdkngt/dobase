# frozen_string_literal: true

require "application_system_test_case"

class NotificationsTest < ApplicationSystemTestCase
  test "the mobile bell reloads the notification list instead of throwing" do
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)
    visit tools_path
    wait_for_turbo

    page.execute_script(<<~JS)
      window.__errors = []
      const original = console.error
      console.error = (...args) => { window.__errors.push(args.map(String).join(" ")); original(...args) }
    JS

    find(".mobile-bottom-bar button[popovertarget='sidebar-notifications']").click
    sleep 0.5

    errors = page.evaluate_script("window.__errors")
    assert errors.none? { |e| e.include?('Missing target element "popover"') }, "console errors: #{errors.inspect}"
    assert_selector "#sidebar-notifications turbo-frame#notifications", visible: :all
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a crafted notification message renders as text, not markup" do
    # The list target only renders once there's at least one notification.
    Chats::Message.create!(chat: Chats::Chat.create!(tool: tools(:shared_board)), user: users(:two), body: "Hi")

    sign_in_as(users(:one))
    visit tools_path
    wait_for_turbo
    wait_for_stimulus "notifications", "[data-controller~='notifications']"
    # Open the popover for real so the list target actually exists, and wait
    # for the frame to actually finish loading its content (not just for the
    # frame element to appear) before poking at the controller.
    find("button.sidebar-add-btn[data-notifications-target='trigger']", visible: :all).click
    assert_selector "[data-notifications-target='list']", text: "sent a message", visible: :all, wait: 5

    # Two elements on the page host a "notifications" controller instance —
    # the sidebar's (which has the open popover and its list) and the mobile
    # bottom bar's (a separate instance, trigger-only) — so pick the one
    # whose popover is actually open rather than assuming the first match.
    page.execute_script(<<~JS)
      const el = document.querySelector("#sidebar-notifications").closest("[data-controller~='notifications']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "notifications")
      controller.handleNotification({
        id: 999,
        url: "/tools/1/board",
        message: '<img src=x onerror="window.__xss = true">Gotcha',
        tool_id: null
      })
    JS

    # The page never draws a message it was sent: the open list is drawn again
    # by the server, which escapes it
    assert_no_selector "[data-notifications-target='list'] img"
    assert_nil page.evaluate_script("window.__xss")
    assert_selector "[data-notifications-target='list']", text: "sent a message", visible: :all
    assert_no_text "Gotcha"
  end

  test "the bell shows all with the unread first, or only the unread, and leads to its page" do
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Seen card", position: 0)
    CardAssignmentNotifier.with(card: card, assigner: users(:two), tool: tools(:shared_board)).deliver(users(:one))
    users(:one).notifications.update_all(read_at: Time.current)
    other = boards(:shared).columns.first.cards.create!(title: "New card", position: 1)
    CardAssignmentNotifier.with(card: other, assigner: users(:two), tool: tools(:shared_board)).deliver(users(:one))

    sign_in_as(users(:one))
    visit tools_path
    wait_for_stimulus "notifications", "[data-controller~='notifications']"
    find("button.sidebar-add-btn[data-notifications-target='trigger']", visible: :all).click

    within("#sidebar-notifications") do
      assert_selector ".notification-row", count: 2
      assert_selector ".notification-row:first-child.notification-row-unread", text: "New card"
      assert_no_text "Clear all"

      click_on "Unread"
      assert_selector ".notification-row", count: 1
      assert_selector ".notification-row", text: "New card"

      click_on "All"
      assert_selector ".notification-row", count: 2

      click_on "View all"
    end

    assert_current_path notifications_path
    assert_selector "h1", text: "Notifications"
    assert_selector "main .notification-row", count: 2
  end

  test "the notifications page clears them all, after asking" do
    card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "A card", position: 0)
    CardAssignmentNotifier.with(card: card, assigner: users(:two), tool: tools(:shared_board)).deliver(users(:one))

    sign_in_as(users(:one))
    visit notifications_path
    assert_selector "main .notification-row", text: "A card"

    click_on "Clear all"
    within("dialog#turbo-confirm-dialog[open]") { click_on "Clear all" }

    assert_text "Notifications cleared."
    assert_text "No notifications"
    assert_equal 0, users(:one).notifications.count
  end
end
