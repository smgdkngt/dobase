# frozen_string_literal: true

class AddTrashedAtToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :trashed_at, :datetime
    add_index :mail_messages, :trashed_at

    # Mail already in the trash starts its 30 days now
    up_only do
      execute "UPDATE mail_messages SET trashed_at = CURRENT_TIMESTAMP WHERE trashed = 1"
    end
  end
end
