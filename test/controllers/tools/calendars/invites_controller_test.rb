# frozen_string_literal: true

require "test_helper"

module Tools
  module Calendars
    class InvitesControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @calendar_tool = tools(:my_calendar)
        @own_invite = invite_for(mails_messages(:inbox_unread), summary: "Planning session")
        @foreign_invite = invite_for(mails_messages(:other_inbox), summary: "Board meeting")
      end

      test "accepting an invite from your own mail adds it to the calendar with its attendees" do
        attendees = [
          { "email" => "alice@example.com", "name" => "Alice", "status" => "accepted", "role" => "req-participant", "rsvp" => false },
          { "email" => "one@example.com", "name" => "User One", "status" => "needs-action", "role" => "req-participant", "rsvp" => true }
        ]
        @own_invite.update!(attendees_json: attendees.to_json)
        calendar = calendars_calendars(:personal)

        email_url = tool_mail_url(tools(:my_mail), mails_messages(:inbox_unread))

        assert_difference -> { calendar.events.count }, 1 do
          post tool_calendar_invites_path(@calendar_tool), params: { invite_id: @own_invite.id, calendar_id: calendar.id },
                                                           headers: { "HTTP_REFERER" => email_url }
        end

        assert_redirected_to email_url
        event = calendar.events.find_by!(uid: @own_invite.uid)
        assert_equal [ "Planning session", attendees ], [ event.summary, event.attendees ]
        @own_invite.reload
        assert_equal [ "accepted", calendar, event ], [ @own_invite.status, @own_invite.added_to_calendar, @own_invite.created_event ]
        assert_enqueued_with job: PushEventJob, args: [ event.id, :create ]
      end

      test "accepting an invite without a title adds an untitled event" do
        @own_invite.update!(summary: nil)
        calendar = calendars_calendars(:personal)

        post tool_calendar_invites_path(@calendar_tool), params: { invite_id: @own_invite.id, calendar_id: calendar.id }

        assert_equal "(No title)", calendar.events.find_by!(uid: @own_invite.uid).summary
        assert_equal "accepted", @own_invite.reload.status
      end

      test "cannot accept an invite from mail the user has no access to" do
        assert_no_difference -> { ::Calendars::Event.count } do
          post tool_calendar_invites_path(@calendar_tool),
               params: { invite_id: @foreign_invite.id, calendar_id: calendars_calendars(:personal).id }
        end

        assert_redirected_to root_path
        assert_equal "pending", @foreign_invite.reload.status
        assert_not ::Calendars::Event.exists?(summary: "Board meeting")
      end

      test "declining an invite from your own mail" do
        delete tool_calendar_invite_path(@calendar_tool, @own_invite)

        assert_equal "declined", @own_invite.reload.status
      end

      test "cannot decline an invite from mail the user has no access to" do
        delete tool_calendar_invite_path(@calendar_tool, @foreign_invite)

        assert_redirected_to root_path
        assert_equal "pending", @foreign_invite.reload.status
      end

      private

      def invite_for(message, summary:)
        message.calendar_invites.create!(
          uid: "#{SecureRandom.uuid}@example.com",
          summary: summary,
          starts_at: 2.days.from_now,
          ends_at: 2.days.from_now + 1.hour,
          status: "pending"
        )
      end
    end
  end
end
