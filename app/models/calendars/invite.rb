# frozen_string_literal: true

module Calendars
  class Invite < ApplicationRecord
    self.table_name = "calendar_invites"

    belongs_to :mail_message, class_name: "Mails::Message"
    belongs_to :added_to_calendar, class_name: "Calendars::Calendar", optional: true
    belongs_to :created_event, class_name: "Calendars::Event", optional: true

    validates :uid, presence: true, uniqueness: { scope: :mail_message_id }

    STATUSES = %w[pending accepted declined tentative cancelled].freeze
    METHODS = %w[REQUEST REPLY CANCEL PUBLISH].freeze

    validates :status, inclusion: { in: STATUSES }, allow_nil: true
    validates :method, inclusion: { in: METHODS }, allow_nil: true

    scope :pending, -> { where(status: "pending") }
    scope :upcoming, -> { where("starts_at > ?", Time.current).order(starts_at: :asc) }

    def duration_display
      return nil unless starts_at && ends_at && ends_at > starts_at

      minutes = ((ends_at - starts_at) / 60).to_i

      if minutes < 60
        "#{minutes} #{"minute".pluralize(minutes)}"
      elsif minutes < 1440
        hours = minutes / 60.0
        hours = hours == hours.to_i ? hours.to_i : hours.round(1)
        "#{hours} #{"hour".pluralize(hours)}"
      else
        days = minutes / 1440.0
        days = days == days.to_i ? days.to_i : days.round(1)
        "#{days} #{"day".pluralize(days)}"
      end
    end

    # All-day invites run from midnight UTC on their first day to midnight UTC after their
    # last (DTEND is exclusive), like all-day events, so their dates are read in UTC
    def first_day
      return nil unless starts_at

      all_day? ? starts_at.utc.to_date : starts_at.to_date
    end

    def last_day
      return nil unless ends_at

      all_day? ? (ends_at.utc - 1.day).to_date : ends_at.to_date
    end

    # An attendee answering the user's own invitation, so there is nothing to accept
    def reply?
      method == "REPLY"
    end

    def accepted?
      status == "accepted"
    end

    def declined?
      status == "declined"
    end

    def pending?
      status == "pending"
    end

    def cancelled?
      status == "cancelled"
    end

    # Invitations for the same event that arrived in the same mailbox
    def same_event_invitations
      self.class.joins(:mail_message)
        .where(uid: uid, mail_messages: { mail_account_id: mail_message.mail_account_id })
        .where.not(id: id)
    end

    # For a cancellation: the earlier invitation that was added to a calendar, if any
    def accepted_invitation
      same_event_invitations.where(status: "accepted").where.not(created_event_id: nil).first
    end

    def attendees
      return [] if attendees_json.blank?
      JSON.parse(attendees_json)
    rescue JSON::ParserError
      []
    end
  end
end
