# frozen_string_literal: true

class AllowNullCredentialsForLocalCalendarAccounts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :calendar_accounts, :username, true
    change_column_null :calendar_accounts, :encrypted_password, true
  end
end
