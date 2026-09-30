# frozen_string_literal: true

# The mail a draft replies to or forwards, quoted below its text when it's sent. A plain
# column: SQLite adds a foreign key (or an index) by reading the whole table, which took the
# deploy past its health check. Ids aren't reused, so a quoted mail that's gone reads as nil.
class AddQuotedMessageToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :quoted_message_id, :integer
  end
end
