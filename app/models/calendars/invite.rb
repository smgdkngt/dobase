# frozen_string_literal: true

module Calendars
  class Invite < ApplicationRecord
    self.table_name = "calendar_invites"

    belongs_to :mail_message, class_name: "Mails::Message"
    belongs_to :added_to_calendar, class_name: "Calendars::Calendar", optional: true
    belongs_to :created_event, class_name: "Calendars::Event", optional: true

    validates :uid, presence: true, uniqueness: { scope: :mail_message_id }

    STATUSES = %w[pending accepted declined tentative].freeze
    METHODS = %w[REQUEST REPLY CANCEL PUBLISH].freeze

    validates :status, inclusion: { in: STATUSES }, allow_nil: true
    validates :method, inclusion: { in: METHODS }, allow_nil: true

    scope :pending, -> { where(status: "pending") }
    scope :upcoming, -> { where("starts_at > ?", Time.current).order(starts_at: :asc) }

    def duration_display
      return nil unless starts_at && ends_at

      minutes = ((ends_at - starts_at) / 60).to_i

      if minutes < 60
        "#{minutes} minutes"
      elsif minutes < 1440
        hours = minutes / 60.0
        hours == hours.to_i ? "#{hours.to_i} hours" : "#{hours.round(1)} hours"
      else
        days = minutes / 1440.0
        days == days.to_i ? "#{days.to_i} days" : "#{days.round(1)} days"
      end
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

    def attendees
      return [] if attendees_json.blank?
      JSON.parse(attendees_json)
    rescue JSON::ParserError
      []
    end
  end
end
