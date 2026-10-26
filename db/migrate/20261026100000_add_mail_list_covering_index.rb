# frozen_string_literal: true

# A mailbox's list and counts read every message of a folder, by its flags, thread and
# date. Those columns sit after the bodies in a row, and SQLite reaches them by reading
# the body first: a folder of thousands of mails read all their text to count them.
# With every column the list asks for in an index, it never opens a row: by folder for
# a folder's list and counts, by thread for the archive (archived, or in the server's
# archive folder: an OR, which goes through the threads).
class AddMailListCoveringIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :mail_messages,
      %i[mail_account_id folder trashed draft archived thread_id sent_at read starred has_attachments message_id],
      name: "index_mail_messages_for_the_list"
    add_index :mail_messages,
      %i[mail_account_id thread_id folder trashed draft archived sent_at read starred has_attachments message_id],
      name: "index_mail_messages_for_the_list_by_thread"
  end
end
