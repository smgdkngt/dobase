# frozen_string_literal: true

# When SendMailJob took a mail that is being sent: from then on it can't be taken back
# (Undo after Send). Nil while it waits, so taking back and sending can't both happen.
class AddSendStartedAtToMailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :send_started_at, :datetime
  end
end
