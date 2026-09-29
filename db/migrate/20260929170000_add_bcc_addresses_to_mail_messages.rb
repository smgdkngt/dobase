# frozen_string_literal: true

# A draft keeps its Bcc, also when it's sent in the background and fails to go out
class AddBccAddressesToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :bcc_addresses, :text
  end
end
