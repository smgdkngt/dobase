# frozen_string_literal: true

class ResetMailAutoRefreshSavedByAccident < ActiveRecord::Migration[8.1]
  # The mail settings preselected "Disabled" for accounts without an interval, so saving
  # them for any other reason stored 0. Disabled never worked either: the mail page synced
  # nonstop. Unset these again, so the mail page refreshes every minute, as it did before.
  def up
    execute "UPDATE mail_accounts SET auto_refresh_interval = NULL WHERE auto_refresh_interval = 0"
  end

  def down
    # Nothing to undo: an account that chose Disabled can't be told apart
  end
end
