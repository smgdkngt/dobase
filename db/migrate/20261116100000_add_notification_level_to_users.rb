# frozen_string_literal: true

# How much someone wants to hear: everything, only what is meant for them (a mention,
# an assignment, an invitation), or nothing. Both the bell and the digest go by it.
class AddNotificationLevelToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notification_level, :string, default: "all", null: false
  end
end
