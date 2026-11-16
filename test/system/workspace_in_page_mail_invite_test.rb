# frozen_string_literal: true

require "application_system_test_case"

# An invitation in a mail tile, added to a calendar: the calendar is another tool, and
# the tile still says what happened (Tools::Calendars::InvitesController goes back to
# the mail, not "back where you came from", which is the calendar's own tile address)
class WorkspaceInPageMailInviteTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  TILE = ".workspace-tile:not([hidden], [data-leaving])"
  MAIL = "#{TILE} > turbo-frame.tile-frame"

  setup do
    @tool = tools(:my_mail)
    @message = mails_messages(:inbox_unread)
    starts_at = 1.week.from_now.change(hour: 14)
    @invite = @message.calendar_invites.create!(uid: "tasting@example.com", method: "REQUEST", summary: "Tasting session",
                                                starts_at: starts_at, ends_at: starts_at + 1.hour)
    sign_in_as users(:one)
    page.driver.browser.manage.delete_cookie("workspace")
    visit workspace_path(open: tool_mail_path(@tool, @message))
    wait_for_stimulus "workspace"
    within(".workspace-hint") { click_on "Got it" }
    assert_selector "#{MAIL} .mail-detail-header h1", text: "Welcome to Dobase"
  end

  test "an invitation added from a mail tile says so, and stays in the mail" do
    within(MAIL) { click_on "Add to Calendar" }

    assert_selector ".flash", text: "Added to Personal:"
    assert_selector "#{MAIL} .invite-added", text: "In Personal"
    assert_no_button "Add to Calendar"
    assert_equal "accepted", @invite.reload.status

    # Opened again, it still says where the invitation went
    visit workspace_path
    wait_for_stimulus "workspace"
    assert_selector "#{MAIL} .invite-added", text: "In Personal"
  end

  test "undo takes the event out of the calendar and the invitation is open again" do
    within(MAIL) { click_on "Add to Calendar" }
    assert_selector ".flash", text: "Added to Personal:"
    event = @invite.reload.created_event

    within(".flash", text: "Added to Personal:") { click_on "Undo" }

    assert_selector ".flash", text: "Taken out of the calendar again."
    assert_selector "#{MAIL} button", text: "Add to Calendar"
    assert_db_change(-> { @invite.reload.pending? })
    assert_not Calendars::Event.exists?(event.id)
  end

  # Right after adding, while the form that was sent to the calendar tool is fresh
  test "Open in Calendar opens the event in a tile of the calendar" do
    within(MAIL) { click_on "Add to Calendar" }
    within("#{MAIL} .invite-added") { click_on "Open in Calendar" }

    assert_selector "#{TILE} .event-details h3", text: "Tasting session"
    assert_selector TILE, count: 2
  end
end
