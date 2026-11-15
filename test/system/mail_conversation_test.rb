# frozen_string_literal: true

require "application_system_test_case"

# A long conversation: what was unread opens, the rest is a line each, it starts on the
# first open message, and what each message quotes at its end is behind three dots
class MailConversationTest < ApplicationSystemTestCase
  include MailThreadHelper

  setup do
    @tool = tools(:my_mail)
    sign_in_as(users(:one))
    @messages = create_long_conversation
  end

  test "a long conversation opens what was unread and the last message, on the first of them, with their quotes folded away" do
    page.driver.browser.manage.window.resize_to(1400, 700)
    visit tool_mail_path(@tool, @messages.last)

    @messages.values_at(2, 3, 5).each { |message| assert_selector "#mail-message-#{message.id}[data-collapse-open-value=true]" }
    @messages.values_at(0, 1, 4).each do |message|
      within "#mail-message-#{message.id}[data-collapse-open-value=false]" do
        assert_selector ".mail-message-snippet", text: message.snippet.first(30)
        assert_no_selector "[data-collapse-target=content]", visible: true
      end
      # One line: a closed message is no taller than a line of text and its padding
      assert_operator height_of("#mail-message-#{message.id}"), :<, 56
    end

    assert_starts_on @messages[2]

    # Apple Mail's quote in the last message, inside the mail's frame
    within_frame(find("#mail-message-#{@messages.last.id} iframe")) do
      assert_text "Booked for Thursday"
      assert_no_text "On Tuesday, Test User wrote:"
      find("summary[title='Show the quoted text']").click
      assert_text "On Tuesday, Test User wrote:"
    end

    # A mail of text: its "> " lines
    within "#mail-message-#{@messages[2].id}" do
      assert_text "They came back to me"
      assert_no_text "On Monday, Ann Lee wrote:"
      find("summary[title='Show the quoted text']").click
      assert_text "On Monday, Ann Lee wrote:"
    end

    # A closed one opens on its line
    find("#mail-message-#{@messages[0].id} .mail-message-toggle").click
    assert_selector "#mail-message-#{@messages[0].id}[data-collapse-open-value=true] .mail-plain-text", text: "Shall we pick a venue"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "the page drawing itself again leaves open what was opened, and the reader where they are" do
    page.driver.browser.manage.window.resize_to(1400, 700)
    visit tool_mail_path(@tool, @messages.last)
    assert_starts_on @messages[2]
    page.execute_script("document.querySelector('.mail-message-in').scrollTop -= 40")
    scrolled = page.evaluate_script("document.querySelector('.mail-message-in').scrollTop")

    # Read by now, the server draws only the last one open
    auto_refresh_mail

    @messages.values_at(2, 3, 5).each { |message| assert_selector "#mail-message-#{message.id}[data-collapse-open-value=true]" }
    assert_selector "#mail-message-#{@messages[2].id} .mail-plain-text", visible: true
    assert_equal scrolled, page.evaluate_script("document.querySelector('.mail-message-in').scrollTop")
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "opened from the list, a conversation starts on what was unread too" do
    page.driver.browser.manage.window.resize_to(1400, 700)
    visit tool_mails_path(@tool)
    find(".mail-list-item", text: "Venue for the offsite").click

    assert_selector "#mail-message-#{@messages[3].id}[data-collapse-open-value=true]"
    assert_starts_on @messages[2]
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "on a phone the conversation starts on what was unread, and a closed message is one line" do
    page.driver.browser.manage.window.resize_to(390, 844)
    visit tool_mail_path(@tool, @messages.last)

    assert_selector ".mail-detail-header h1", text: "Venue for the offsite"
    assert_starts_on @messages[2]
    assert_operator height_of("#mail-message-#{@messages[0].id}"), :<, 56
    # Nothing is wider than the screen
    assert_operator page.evaluate_script("document.querySelector('.mail-message-in').scrollWidth"), :<=, 390
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  private

  def height_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  # The conversation shows the message near its top, under the closed line before it
  # (which is at the very top: there is more above)
  def assert_starts_on(message)
    script = <<~JS
      (() => {
        const reader = document.querySelector(".mail-message-in")
        const message = document.getElementById("mail-message-#{message.id}")
        const top = (element) => element.getBoundingClientRect().top - reader.getBoundingClientRect().top
        return [reader.scrollTop, top(message.previousElementSibling), top(message)]
      })()
    JS
    page.document.synchronize do
      scroll_top, line, opened = page.evaluate_script(script)
      unless scroll_top.positive? && line.abs < 2 && opened.between?(30, 60)
        raise Capybara::ExpectationNotMet, "scrolled #{scroll_top}, the line before at #{line}, the message at #{opened}"
      end
    end
  end

  def auto_refresh_mail
    page.evaluate_async_script(<<~JS)
      const element = document.querySelector("[data-controller~='mail-refresh']")
      window.Stimulus.getControllerForElementAndIdentifier(element, "mail-refresh").sync().then(arguments[0])
    JS
    wait_for_turbo
  end
end
