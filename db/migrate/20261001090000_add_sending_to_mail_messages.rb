# frozen_string_literal: true

# Mail from the compose page is in Sent from the moment it's sent off, so it shows in its
# conversation straight away. This marks it until the mail server has taken it.
class AddSendingToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :sending, :boolean, default: false, null: false
  end
end
