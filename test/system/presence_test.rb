# frozen_string_literal: true

require "application_system_test_case"

class PresenceTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @colleague = users(:two)
    @tool = tools(:shared_board)
  end

  test "someone else opening the board shows up in the topbar, and leaves when they go" do
    sign_in_as(@user)
    visit tool_board_path(@tool)
    wait_for_stimulus "presence"
    assert_no_selector ".presence-face"

    using_session("colleague") do
      open_board_as(@colleague, @tool)
    end

    assert_selector ".presence-face[aria-label='#{@colleague.name} is here']"

    # Turbo.visit, not Capybara's: a fresh page load leaves the old socket to
    # time out, where a link click inside the app closes it as you leave. And
    # not root_path either, which lands you back on the page you last had open.
    using_session("colleague") do
      page.execute_script("Turbo.visit('#{Rails.application.routes.url_helpers.tools_path}')")
      assert_current_path tools_path
    end

    assert_no_selector ".presence-face"
  end

  test "a card someone else has open is ringed while they have it" do
    column = boards(:shared).columns.create!(name: "Doing", position: 0)
    card = column.cards.create!(title: "Shared work", position: 0)

    sign_in_as(@user)
    visit tool_board_path(@tool)
    wait_for_stimulus "presence"

    using_session("colleague") do
      open_board_as(@colleague, @tool, card: card.id)
    end

    assert_selector "#board-card-#{card.id}.presence-here"
    assert_selector "#board-card-#{card.id} [data-presence-badge]", text: @colleague.initials
  end

  test "the sidebar shows who has a tool open, wherever you are yourself" do
    sign_in_as(@user)
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "sidebar-presence"
    slot = "[data-sidebar-presence-target='slot'][data-tool-id='#{@tool.id}']"
    assert_no_selector "#{slot} .sidebar-presence-face"

    using_session("colleague") do
      open_board_as(@colleague, @tool)
    end

    assert_selector "#{slot} .sidebar-presence-face", text: @colleague.initials
  end

  test "someone already in a tool shows in the sidebar of a page opened after them" do
    using_session("colleague") do
      open_board_as(@colleague, @tool)
    end

    sign_in_as(@user)
    visit tool_board_path(tools(:project_board))
    wait_for_stimulus "sidebar-presence"

    # The roll call gets their answer, well before their next heartbeat
    assert_selector "[data-sidebar-presence-target='slot'][data-tool-id='#{@tool.id}'] .sidebar-presence-face",
      text: @colleague.initials
  end

  test "an open card says who else has it open" do
    column = boards(:shared).columns.create!(name: "Doing", position: 0)
    card = column.cards.create!(title: "Shared work", position: 0)

    sign_in_as(@user)
    visit tool_board_path(@tool, card: card.id)
    wait_for_stimulus "presence"
    assert_selector "dialog[open] h2", text: "Shared work"

    using_session("colleague") do
      open_board_as(@colleague, @tool, card: card.id)
    end

    within("dialog[open]") do
      assert_selector ".presence-watchers", text: "#{@colleague.name} is here too"
    end
  end

  test "you see someone else writing a comment on the card you have open" do
    column = boards(:shared).columns.create!(name: "Doing", position: 0)
    card = column.cards.create!(title: "Shared work", position: 0)

    sign_in_as(@user)
    visit tool_board_path(@tool, card: card.id)
    wait_for_stimulus "presence"
    assert_selector "dialog[open] h2", text: "Shared work"

    using_session("colleague") do
      open_board_as(@colleague, @tool, card: card.id)
      within("dialog[open]") { find(".rich-text-input .ProseMirror").send_keys("On it") }
    end

    within("dialog[open]") do
      assert_selector ".presence-typing", text: "#{@colleague.name} is writing a comment…"
    end
    # And it goes by itself once they stop
    assert_no_selector ".presence-typing", wait: 8
  end

  private

  # Two things to work around here: signing in lands you on the page you last
  # had open, which arrives after a visit if we don't wait for it first; and a
  # fresh page load leaves the socket of the page before it to time out, so the
  # tool would count this person twice. Moving inside the app does neither.
  def open_board_as(user, tool, card: nil)
    sign_in_as(user)
    assert_selector "aside.sidebar"
    page.execute_script("Turbo.visit('#{tool_board_path(tool, card: card)}')")
    assert_current_path tool_board_path(tool), ignore_query: true
    wait_for_stimulus "presence"
  end
end
