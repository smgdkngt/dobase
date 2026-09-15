# frozen_string_literal: true

class NullifyCalendarInviteReferencesOnDelete < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :calendar_invites, :calendar_events, column: :created_event_id
    add_foreign_key :calendar_invites, :calendar_events, column: :created_event_id, on_delete: :nullify

    remove_foreign_key :calendar_invites, :calendar_calendars, column: :added_to_calendar_id
    add_foreign_key :calendar_invites, :calendar_calendars, column: :added_to_calendar_id, on_delete: :nullify
  end
end
