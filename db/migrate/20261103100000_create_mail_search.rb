# frozen_string_literal: true

# A full-text index of mail (SQLite FTS5), so a search finds whole words and the start of
# words in every folder at once, ranked by where they were found. One row per message,
# under the message's id; Mails::SearchIndex keeps it current. Filled here from the mail
# there is, which on a big mailbox takes a while: run this before the deploy.
class CreateMailSearch < ActiveRecord::Migration[8.1]
  def up
    create_virtual_table :mail_search, :fts5, [ "subject", "people", "body", "attachments", "tokenize='unicode61 remove_diacritics 2'" ]

    execute <<~SQL
      INSERT INTO mail_search (rowid, subject, people, body, attachments)
      SELECT m.id,
        coalesce(m.subject, ''),
        coalesce(m.from_name, '') || ' ' || coalesce(m.from_address, '') || ' ' || coalesce(m.to_addresses, '') || ' ' ||
          coalesce(m.cc_addresses, '') || ' ' || coalesce(m.bcc_addresses, ''),
        substr(coalesce(m.body_plain, ''), 1, 200000),
        coalesce((SELECT group_concat(a.filename, ' ') FROM mail_attachments a WHERE a.mail_message_id = m.id), '')
      FROM mail_messages m
    SQL
  end

  def down
    drop_table :mail_search
  end
end
