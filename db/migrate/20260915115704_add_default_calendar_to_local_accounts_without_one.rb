# frozen_string_literal: true

class AddDefaultCalendarToLocalAccountsWithoutOne < ActiveRecord::Migration[8.1]
  # Creating a local calendar account saved the account and then failed to add its default calendar
  # (remote_id was NOT NULL), leaving accounts without any calendar to add events to.
  def up
    execute <<~SQL
      INSERT INTO calendar_calendars (calendar_account_id, name, color, enabled, is_default, position, created_at, updated_at)
      SELECT calendar_accounts.id, tools.name, '#3b82f6', TRUE, TRUE, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM calendar_accounts
      INNER JOIN tools ON tools.id = calendar_accounts.tool_id
      WHERE calendar_accounts.provider = 'local'
        AND NOT EXISTS (SELECT 1 FROM calendar_calendars WHERE calendar_calendars.calendar_account_id = calendar_accounts.id)
    SQL
  end

  def down
    # Nothing to undo: these calendars may hold events by now
  end
end
