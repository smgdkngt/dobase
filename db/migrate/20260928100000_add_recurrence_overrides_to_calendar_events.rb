# frozen_string_literal: true

# The moved occurrences of a synced series. Synced series were built in UTC and
# drifted an hour with summer time, so every calendar syncs in full once more.
class AddRecurrenceOverridesToCalendarEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :calendar_events, :recurrence_overrides_json, :text
    execute "UPDATE calendar_calendars SET ctag = NULL"
  end

  def down
    remove_column :calendar_events, :recurrence_overrides_json
  end
end
