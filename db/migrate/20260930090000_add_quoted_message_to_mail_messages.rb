# frozen_string_literal: true

# The mail a draft replies to or forwards, quoted below its text when it's sent
class AddQuotedMessageToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :mail_messages, :quoted_message, index: false, foreign_key: { to_table: :mail_messages, on_delete: :nullify }
  end
end
