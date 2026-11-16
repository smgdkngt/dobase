# frozen_string_literal: true

module Calendars
  # An invitation just added to a calendar, kept in the Undo button of the notice that
  # says so: signed, for the person who added it, for a few minutes. Undoing opens the
  # invitation again, and takes the event out of the calendar when adding made it (an
  # event that was there already, the server's own copy, stays).
  #
  #   token = Calendars::InviteAcceptance.token_for(invite, created: true, user: Current.user)
  #   Calendars::InviteAcceptance.find(token, invite: invite, user: Current.user)&.undo
  class InviteAcceptance
    EXPIRES_IN = 5.minutes

    attr_reader :invite

    def self.verifier
      Rails.application.message_verifier("invite_acceptance")
    end

    def self.token_for(invite, created:, user:)
      verifier.generate({ "invite" => invite.id, "event" => invite.created_event_id, "created" => created, "user" => user.id },
        purpose: :undo, expires_in: EXPIRES_IN)
    end

    def self.find(token, invite:, user:)
      payload = verifier.verified(token.to_s, purpose: :undo)
      return unless payload.is_a?(Hash) && payload["invite"] == invite.id && payload["user"] == user.id
      # Added again since, or declined: that is what the person did last, and stays
      return unless invite.accepted? && invite.created_event_id == payload["event"]

      new(invite, created: payload["created"] == true)
    end

    def initialize(invite, created:)
      @invite = invite
      @created = created
    end

    # Whether the event went out of the calendar with it
    def undo
      event = invite.created_event
      invite.update!(status: "pending", added_to_calendar: nil, created_event: nil)
      return false unless @created && event && !Invite.exists?(created_event_id: event.id)

      remove(event)
      true
    end

    private

    def remove(event)
      data = { remote_href: event.remote_href, etag: event.etag, calendar_id: event.calendar_id, uid: event.uid }
      event.destroy!
      DeleteCalendarEventJob.perform_later(data)
    end
  end
end
