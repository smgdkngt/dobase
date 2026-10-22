# frozen_string_literal: true

module Mcp
  module Tools
    module Calendar
      extend Declaring

      tool "appointment_list", "Show a calendar",
        "A calendar tool's calendars and its appointments from start_date through end_date (both included; " \
        "92 days at most). Without dates: today and the six days after.",
        params: {
          tool_id: tool_id("calendar"),
          start_date: date("The first day"),
          end_date: date("The last day")
        }, read_only: true do
        get "/tools/#{arg(:tool_id)}/calendar", start_date: arg(:start_date), end_date: arg(:end_date)
      end

      tool "appointment_show", "Show an appointment",
        "One appointment: its time, place, notes, how it repeats, and for an invitation its organizer and attendees.",
        params: { tool_id: tool_id("calendar"), appointment_id: id("The appointment's id", required: true) },
        read_only: true do
        get "/tools/#{arg(:tool_id)}/calendar/events/#{arg(:appointment_id)}"
      end
    end
  end
end
