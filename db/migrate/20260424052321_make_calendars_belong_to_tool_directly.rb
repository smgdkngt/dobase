# frozen_string_literal: true

class MakeCalendarsBelongToToolDirectly < ActiveRecord::Migration[8.1]
  def up
    add_reference :calendar_calendars, :tool, foreign_key: { to_table: :tools }
    change_column_null :calendar_calendars, :calendar_account_id, true

    # Backfill tool_id from the associated account.
    execute <<~SQL
      UPDATE calendar_calendars
      SET tool_id = (
        SELECT tool_id
        FROM calendar_accounts
        WHERE calendar_accounts.id = calendar_calendars.calendar_account_id
      )
      WHERE calendar_account_id IS NOT NULL
    SQL

    # Detach calendars from local (non-syncing) accounts — they stay with their tool.
    execute <<~SQL
      UPDATE calendar_calendars
      SET calendar_account_id = NULL
      WHERE calendar_account_id IN (
        SELECT id FROM calendar_accounts WHERE provider = 'local'
      )
    SQL

    # Drop the now-orphaned shell accounts.
    execute <<~SQL
      DELETE FROM calendar_accounts WHERE provider = 'local'
    SQL

    change_column_null :calendar_calendars, :tool_id, false
    change_column_null :calendar_calendars, :remote_id, true
  end

  def down
    change_column_null :calendar_calendars, :remote_id, false
    change_column_null :calendar_calendars, :calendar_account_id, false
    change_column_null :calendar_calendars, :tool_id, true
    remove_reference :calendar_calendars, :tool, foreign_key: { to_table: :tools }
  end
end
