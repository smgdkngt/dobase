class AddReadOnlyToCalendars < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_calendars, :read_only, :boolean, default: false, null: false
  end
end
