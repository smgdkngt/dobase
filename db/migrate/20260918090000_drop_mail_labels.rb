# frozen_string_literal: true

# The mail label endpoints were removed and nothing reads these tables any more.
class DropMailLabels < ActiveRecord::Migration[8.1]
  def up
    drop_table :mail_label_assignments
    drop_table :mail_labels
  end

  def down
    create_table :mail_labels do |t|
      t.bigint :mail_account_id, null: false
      t.string :name, null: false
      t.string :color
      t.timestamps
      t.index %i[mail_account_id name], unique: true
      t.index :mail_account_id
    end

    create_table :mail_label_assignments do |t|
      t.bigint :mail_label_id, null: false
      t.bigint :mail_message_id, null: false
      t.timestamps
      t.index %i[mail_message_id mail_label_id], unique: true
      t.index :mail_label_id
      t.index :mail_message_id
    end

    add_foreign_key :mail_label_assignments, :mail_labels
    add_foreign_key :mail_label_assignments, :mail_messages
    add_foreign_key :mail_labels, :mail_accounts
  end
end
