# frozen_string_literal: true

module Mails
  # The full-text index of mail (the `mail_search` FTS5 table): a message's subject, the
  # people on it (names and addresses), its text and the names of its files, under the
  # message's id. A message writes its own row when one of those changes (Mails::Message,
  # Mails::Attachment), so it never needs a callback of the sync's.
  module SearchIndex
    # How much of a text is indexed: past this a mail is a log or a list, not a letter
    BODY_LIMIT = 200_000

    # Where a word was found counts for this much in the ranking, in the table's column order
    WEIGHTS = "10.0, 5.0, 1.0, 5.0"

    # The ids of the messages matching a query (the ?), with how well each matched: lower
    # is better (FTS5's bm25), as a table to join. The LIMIT keeps SQLite from folding it
    # into the query around it, where bm25 can't be read inside a GROUP BY.
    HITS = "(SELECT rowid AS hit_id, bm25(mail_search, #{WEIGHTS}) AS hit_score FROM mail_search WHERE mail_search MATCH ? LIMIT -1) AS mail_hits"

    ROWS = <<~SQL
      SELECT m.id,
        coalesce(m.subject, ''),
        coalesce(m.from_name, '') || ' ' || coalesce(m.from_address, '') || ' ' || coalesce(m.to_addresses, '') || ' ' ||
          coalesce(m.cc_addresses, '') || ' ' || coalesce(m.bcc_addresses, ''),
        substr(coalesce(m.body_plain, ''), 1, #{BODY_LIMIT}),
        coalesce((SELECT group_concat(a.filename, ' ') FROM mail_attachments a WHERE a.mail_message_id = m.id), '')
      FROM mail_messages m
    SQL

    class << self
      # A message's row written again. Also when it is new: SQLite can give a new message
      # the id of one that was removed without its row (the sync's delete_all).
      def write(message_id)
        remove(message_id)
        connection.exec_insert("INSERT INTO mail_search (rowid, subject, people, body, attachments) #{ROWS} WHERE m.id = ?",
          "Mail search", [ message_id ])
      end

      def remove(message_id)
        connection.exec_delete("DELETE FROM mail_search WHERE rowid = ?", "Mail search", [ message_id ])
      end

      # Every row written again from the mail there is (tests, and a repair)
      def rebuild
        connection.execute("DELETE FROM mail_search")
        connection.execute("INSERT INTO mail_search (rowid, subject, people, body, attachments) #{ROWS}")
      end

      # What FTS5 is asked for what someone typed: every word must be there, as a word or
      # the start of one; "quoted words" as they stand, one after the other. Nil when
      # nothing in it can be looked for. Nothing typed is ever FTS5's own syntax.
      def query(text)
        terms = text.to_s.scan(/"([^"]*)"|(\S+)/).filter_map do |phrase, word|
          if phrase
            words = phrase.scan(/[[:alnum:]]+/)
            %("#{words.join(" ")}") if words.any?
          else
            words = word.scan(/[[:alnum:]]+/)
            %("#{words.join(" ")}"*) if words.any?
          end
        end
        terms.join(" ").presence
      end

      private

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
