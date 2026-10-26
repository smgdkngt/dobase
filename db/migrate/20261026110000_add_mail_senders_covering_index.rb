# frozen_string_literal: true

# Who someone is (the name they sign with) and who an address field offers while
# typing are looked up by sender over all of an account's mail, and by who was written
# to over Sent. Those columns sit after the bodies in a row, and SQLite reads the
# body to reach them; from these indexes it never opens a row.
class AddMailSendersCoveringIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :mail_messages, %i[mail_account_id from_address from_name sent_at], name: "index_mail_messages_for_senders"
    add_index :mail_messages, %i[mail_account_id folder trashed draft sent_at to_addresses cc_addresses bcc_addresses],
      name: "index_mail_messages_for_recipients"
  end
end
