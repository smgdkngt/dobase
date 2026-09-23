# frozen_string_literal: true

# Deleting an account whose tool lives on with a co-owner failed: the tool still
# held cards, messages and comments pointing at that person. What someone wrote
# stays, without its author; what was only theirs (reactions, read markers,
# collapsed columns, invitations they sent) goes with them.
class KeepContentWhenItsAuthorLeaves < ActiveRecord::Migration[8.1]
  AUTHORED = {
    calendar_events: %i[created_by_id updated_by_id],
    cards: %i[assigned_user_id created_by_id updated_by_id],
    chat_messages: %i[user_id],
    columns: %i[created_by_id updated_by_id],
    comments: %i[user_id],
    documents: %i[created_by_id updated_by_id],
    file_folders: %i[created_by_id updated_by_id],
    file_items: %i[created_by_id updated_by_id],
    file_shares: %i[created_by_id],
    todo_comments: %i[user_id],
    todo_items: %i[assigned_user_id created_by_id updated_by_id],
    todo_lists: %i[created_by_id updated_by_id]
  }.freeze

  PERSONAL = {
    chat_reactions: :user_id,
    chat_read_receipts: :user_id,
    column_collapses: :user_id,
    invitations: :invited_by_id
  }.freeze

  def up
    AUTHORED.each do |table, columns|
      columns.each do |column|
        change_column_null table, column, true
        refit table, column, on_delete: :nullify
      end
    end

    PERSONAL.each { |table, column| refit table, column, on_delete: :cascade }
  end

  def down
    AUTHORED.each do |table, columns|
      columns.each { |column| refit table, column, on_delete: nil }
    end
    %i[chat_messages comments todo_comments file_shares].each do |table|
      column = table == :file_shares ? :created_by_id : :user_id
      change_column_null table, column, false
    end

    PERSONAL.each { |table, column| refit table, column, on_delete: nil }
  end

  private

  def refit(table, column, on_delete:)
    remove_foreign_key table, column: column
    add_foreign_key table, :users, column: column, on_delete: on_delete
  end
end
