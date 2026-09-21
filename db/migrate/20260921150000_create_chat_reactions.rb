# frozen_string_literal: true

class CreateChatReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_reactions do |t|
      t.references :message, null: false, foreign_key: { to_table: :chat_messages }
      t.references :user, null: false, foreign_key: true
      t.string :emoji, null: false
      t.timestamps
    end

    add_index :chat_reactions, %i[message_id user_id emoji], unique: true
  end
end
