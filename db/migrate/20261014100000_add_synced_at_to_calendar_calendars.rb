# frozen_string_literal: true

# When a calendar's events were first read from its server. Until then a sync brings
# what the calendar has, which is no news (CaldavSyncService); the calendars there are
# have been synced long since.
class AddSyncedAtToCalendarCalendars < ActiveRecord::Migration[8.1]
  def up
    add_column :calendar_calendars, :synced_at, :datetime
    execute "UPDATE calendar_calendars SET synced_at = CURRENT_TIMESTAMP"
  end

  def down
    remove_column :calendar_calendars, :synced_at
  end
end
