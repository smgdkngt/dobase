# frozen_string_literal: true

# A message can be in several folders on the server, and gets a copy for each of them
class ScopeMailMessageIdToFolder < ActiveRecord::Migration[8.1]
  def change
    remove_index :mail_messages, [ :mail_account_id, :message_id ], unique: true
    add_index :mail_messages, [ :mail_account_id, :message_id, :folder ], unique: true, name: "index_mail_messages_on_account_message_id_and_folder"
  end
end
