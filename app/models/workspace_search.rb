# frozen_string_literal: true

# Finds what someone typed across every tool they share: cards, todos,
# documents, files and folders, chat messages, calendar events and mail.
#
# What is typed is split into words ("quoted words" stay together), and a
# result has every word somewhere in it, in any order and in any of its parts:
# a card in its title, its description, its comments or its column's name.
# Plain LIKE queries for all but mail, which has a full-text index of its own
# (Mails::SearchIndex). Dobase holds a team's work, not the internet, and that's
# fast enough without an index of its own.
#
# A handful of results per kind, and how many there are, up to MOST: the
# rest of a kind is asked for by naming it (`kind:`).
class WorkspaceSearch
  PER_KIND = 5
  MOST = 50
  MINIMUM_LENGTH = 2
  KINDS = %i[card todo document folder file message event mail].freeze

  Hit = Data.define(:kind, :title, :excerpt, :tool, :path, :date, :archived) do
    def initialize(excerpt: nil, date: nil, archived: false, **rest)
      super
    end
  end

  attr_reader :query, :kind

  def initialize(user, query, kind: nil)
    @user = user
    @query = query.to_s.squish
    @kind = KINDS.find { |known| known.to_s == kind.to_s }
  end

  def searchable?
    query.length >= MINIMUM_LENGTH && words.any?
  end

  # The words a result must have, lowercased: "quoted words" are one
  def words
    @words ||= query.downcase.scan(/"([^"]+)"|(\S+)/).map { |phrase, word| (phrase || word).squish }
      .reject { |word| word.empty? || word == '"' }.uniq
  end

  # The results shown: a few of each kind, or all of the kind asked for
  def hits
    return [] unless searchable?

    @hits ||= kinds.flat_map { |kind| found(kind).first(kind == self.kind ? MOST : PER_KIND) }
  end

  # How many there are of each kind that has any, counted up to MOST
  def totals
    return {} unless searchable?

    @totals ||= kinds.to_h { |kind| [ kind, [ found(kind).size, MOST ].min ] }.select { |_, count| count.positive? }
  end

  # More of this kind than are shown
  def more?(kind)
    self.kind.nil? && found(kind).size > PER_KIND
  end

  # More than MOST: the count is "50 or more"
  def beyond_most?(kind)
    found(kind).size > MOST
  end

  private

  def kinds
    kind ? [ kind ] : KINDS
  end

  # Every result of a kind, up to one past MOST so that more can be told apart
  def found(kind)
    @found ||= {}
    @found[kind] ||= send(kind.to_s.pluralize)
  end

  def tools
    @tools ||= @user.accessible_tools.includes(:tool_type).index_by(&:id)
  end

  def fetched = MOST + 1

  # The condition that every word is in one of these places. A place is a column,
  # or a piece of SQL with %{like} where the comparison goes (an EXISTS over rich
  # text or comments). sanitize_sql_like puts a backslash before a % or _ in a word,
  # and SQLite only reads that as an escape when the LIKE says so: without it
  # "IMG_1234" found nothing.
  def every_word_in(*places)
    binds = {}
    conditions = words.each_with_index.map do |word, index|
      binds[:"w#{index}"] = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
      like = "LIKE :w#{index} ESCAPE '\\'"
      "(#{places.map { |place| place.include?("%{like}") ? place.sub("%{like}") { like } : "#{place} #{like}" }.join(" OR ")})"
    end
    [ conditions.join(" AND "), binds ]
  end

  # A rich text of the record in that row: its HTML holds the words
  def rich_text(record_type, id_column, name)
    "EXISTS (SELECT 1 FROM action_text_rich_texts rt WHERE rt.record_type = '#{record_type}' " \
      "AND rt.record_id = #{id_column} AND rt.name = '#{name}' AND rt.body %{like})"
  end

  # A comment on the record in that row says it
  def comment(table, comment_type, foreign_key, id_column)
    "EXISTS (SELECT 1 FROM #{table} c JOIN action_text_rich_texts rt ON rt.record_type = '#{comment_type}' " \
      "AND rt.record_id = c.id AND rt.name = 'body' WHERE c.#{foreign_key} = #{id_column} AND rt.body %{like})"
  end

  def cards
    Boards::Card.joins(column: :board)
      .where(boards: { tool_id: tools.keys })
      .where(*every_word_in("cards.title", "columns.name",
        rich_text("Boards::Card", "cards.id", "description"),
        comment("comments", "Boards::Comment", "card_id", "cards.id")))
      .select("cards.*, boards.tool_id AS found_in")
      .includes(:column, :rich_text_description, comments: [ :user, :rich_text_body ])
      .order(Arel.sql("cards.archived_at IS NOT NULL"), updated_at: :desc).limit(fetched).to_a
      .filter_map do |card|
        texts = [ card.column.name, card.description&.to_plain_text, *said_in(card.comments) ]
        next unless all_words?(card.title, *texts)

        hit(:card, card.title, card, routes.tool_board_path(card.found_in, card: card.id),
          excerpt: excerpt_beside(card.title, texts), date: card.archived_at || card.updated_at, archived: card.archived?)
      end
  end

  def todos
    Todos::Item.joins(:list)
      .where(todo_lists: { tool_id: tools.keys })
      .where(*every_word_in("todo_items.title", "todo_lists.title",
        rich_text("Todos::Item", "todo_items.id", "description"),
        comment("todo_comments", "Todos::Comment", "todo_item_id", "todo_items.id")))
      .select("todo_items.*, todo_lists.tool_id AS found_in")
      .includes(:list, :rich_text_description, comments: [ :user, :rich_text_body ])
      .order(Arel.sql("todo_items.completed_at IS NOT NULL"), updated_at: :desc).limit(fetched).to_a
      .filter_map do |item|
        texts = [ item.list.title, item.description&.to_plain_text, *said_in(item.comments) ]
        next unless all_words?(item.title, *texts)

        hit(:todo, item.title, item, routes.tool_todo_path(item.found_in, item: item.id),
          excerpt: excerpt_beside(item.title, texts), date: item.updated_at)
      end
  end

  def documents
    Docs::Document.where(tool_id: tools.keys)
      .where(*every_word_in("documents.title", rich_text("Docs::Document", "documents.id", "content")))
      .includes(:rich_text_content).ordered.limit(fetched).to_a
      .filter_map do |document|
        text = document.content&.to_plain_text
        next unless all_words?(document.title, text)

        hit(:document, document.title, document, routes.tool_docs_document_path(document.tool_id, document),
          excerpt: excerpt_of(text), date: document.last_edited_at || document.updated_at)
      end
  end

  def folders
    Files::Folder.where(tool_id: tools.keys).where(*every_word_in("file_folders.name"))
      .order(updated_at: :desc).limit(fetched)
      .map { |folder| hit(:folder, folder.name, folder, routes.tool_files_path(folder.tool_id, folder_id: folder.id), date: folder.updated_at) }
  end

  def files
    Files::Item.where(tool_id: tools.keys).where(*every_word_in("file_items.name"))
      .order(updated_at: :desc).limit(fetched)
      .map { |file| hit(:file, file.name, file, routes.tool_files_item_path(file.tool_id, file), date: file.updated_at) }
  end

  def messages
    Chats::Message.joins(:chat)
      .where(chats: { tool_id: tools.keys })
      .where(*every_word_in(rich_text("Chats::Message", "chat_messages.id", "body")))
      .select("chat_messages.*, chats.tool_id AS found_in")
      .includes(:user, :rich_text_body).order(created_at: :desc).limit(fetched).to_a
      .filter_map do |message|
        text = message.body&.to_plain_text
        next unless all_words?(text)

        hit(:message, message.user&.name || "Someone", message,
          routes.tool_chat_path(message.found_in, message: message.id),
          excerpt: excerpt_of(text), date: message.created_at)
      end
  end

  def events
    Calendars::Event.joins(calendar: :account)
      .where(calendar_accounts: { tool_id: tools.keys })
      .where(*every_word_in("calendar_events.summary", "calendar_events.location", "calendar_events.description"))
      .select("calendar_events.*, calendar_accounts.tool_id AS found_in")
      .order(starts_at: :desc).limit(fetched)
      .map do |event|
        hit(:event, event.summary, event,
          routes.tool_calendar_path(event.found_in, week_start: event.starts_at.to_date.beginning_of_week.iso8601),
          excerpt: excerpt_beside(event.summary, [ event.location, event.description ]), date: event.starts_at)
      end
  end

  # Mail through its full-text index: its subject, the people on it, its text and its
  # files' names, every word as a word or the start of one
  def mails
    Mails::Message.search(query).joins(:account)
      .where(mail_accounts: { tool_id: tools.keys }).not_trashed.not_draft
      .where.not(folder: Mails::Account::JUNK)
      .select("mail_messages.*, mail_accounts.tool_id AS found_in")
      .order(sent_at: :desc).limit(fetched)
      .map do |mail|
        sender = mail.from_name.presence || mail.from_address
        excerpt = words.all? { |word| [ mail.subject, sender ].join(" ").downcase.include?(word) } ? sender : excerpt_of(mail.body_plain)
        hit(:mail, mail.subject.presence || "(no subject)", mail, routes.tool_mail_path(mail.found_in, mail),
          excerpt: excerpt.presence || sender, date: mail.sent_at)
      end
  end

  def hit(kind, title, record, path, **details)
    tool = tools[record.try(:found_in) || record.try(:tool_id)]
    Hit.new(kind: kind, title: title.to_s, tool: tool, path: path, **details)
  end

  # What was said in comments, with who said it
  def said_in(comments)
    comments.map { |comment| [ comment.user&.name, comment.body&.to_plain_text ].compact.join(": ") }
  end

  # Rich text is stored as HTML, so a word can match inside a tag ("href",
  # "strong") where nobody would see it. Only a match in the words counts.
  def all_words?(*texts)
    text = texts.join("\n").downcase
    words.all? { |word| text.include?(word) }
  end

  # Beside a title, the text that holds what the title doesn't: nothing when the
  # title has every word
  def excerpt_beside(title, texts)
    missing = words.reject { |word| title.to_s.downcase.include?(word) }
    return if missing.empty?

    text = texts.compact.max_by { |candidate| missing.count { |word| candidate.downcase.include?(word) } }
    excerpt_of(text)
  end

  # The part of a long text around the first place one of the words appears
  def excerpt_of(text)
    text = text.to_s.squish
    return if text.empty?

    index = words.filter_map { |word| text.downcase.index(word) }.min
    return text.truncate(90) unless index

    start = [ index - 30, 0 ].max
    snippet = text[start, 90]
    "#{'…' if start.positive?}#{snippet}#{'…' if start + 90 < text.length}"
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
