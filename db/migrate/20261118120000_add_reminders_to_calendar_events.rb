# frozen_string_literal: true

class AddRemindersToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :reminders, :text
  end
end
