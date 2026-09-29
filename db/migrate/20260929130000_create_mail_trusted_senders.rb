# frozen_string_literal: true

# Senders whose mail shows its images straight away
class CreateMailTrustedSenders < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_trusted_senders do |t|
      t.references :mail_account, null: false, foreign_key: true, index: false
      t.string :email_address, null: false
      t.timestamps
    end
    add_index :mail_trusted_senders, [ :mail_account_id, :email_address ], unique: true, name: "index_mail_trusted_senders_on_account_and_address"
  end
end
