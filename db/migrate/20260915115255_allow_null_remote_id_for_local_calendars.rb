# frozen_string_literal: true

class AllowNullRemoteIdForLocalCalendars < ActiveRecord::Migration[8.1]
  def change
    change_column_null :calendar_calendars, :remote_id, true
  end
end
