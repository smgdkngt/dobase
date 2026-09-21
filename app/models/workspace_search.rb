# frozen_string_literal: true

# Finds what someone typed across every tool they share: cards, todos,
# documents, files and folders, chat messages, calendar events and mail.
#
# Plain LIKE queries, a handful of results per kind. Dobase holds a team's
# work, not the internet, and that's fast enough without an index of its own;
# SQLite's FTS5 is the step after this if it ever isn't.
class WorkspaceSearch
  PER_KIND = 5
  MINIMUM_LENGTH = 2

  Hit = Data.define(:kind, :title, :excerpt, :tool, :path)

  attr_reader :query

  def initialize(user, query)
    @user = user
    @query = query.to_s.squish
  end

  def searchable?
    query.length >= MINIMUM_LENGTH
  end

  def hits
    return [] unless searchable?

    @hits ||= cards + todos + documents + folders + files + messages + events + mails
  end

  private

  def tools
    @tools ||= @user.accessible_tools.includes(:tool_type).index_by(&:id)
  end

  def pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
  end

  def cards
    Boards::Card.active.joins(column: :board)
      .where(boards: { tool_id: tools.keys }).where("cards.title LIKE ?", pattern)
      .select("cards.*, boards.tool_id AS found_in").order(updated_at: :desc).limit(PER_KIND)
      .map { |card| hit(:card, card.title, card, routes.tool_board_path(card.found_in, card: card.id)) }
  end

  def todos
    Todos::Item.joins(:list)
      .where(todo_lists: { tool_id: tools.keys }).where("todo_items.title LIKE ?", pattern)
      .select("todo_items.*, todo_lists.tool_id AS found_in")
      .order(Arel.sql("todo_items.completed_at IS NOT NULL"), updated_at: :desc).limit(PER_KIND)
      .map { |item| hit(:todo, item.title, item, routes.tool_todo_path(item.found_in, item: item.id)) }
  end

  def documents
    Docs::Document.where(tool_id: tools.keys)
      .left_joins(:rich_text_content)
      .where("documents.title LIKE :q OR action_text_rich_texts.body LIKE :q", q: pattern)
      .includes(:rich_text_content).ordered.limit(PER_KIND)
      .select { |document| mentions?(document.title) || mentions?(document.content&.to_plain_text) }
      .map { |document| hit(:document, document.title, document, routes.tool_docs_document_path(document.tool_id, document), excerpt_of(document.content&.to_plain_text)) }
  end

  def folders
    Files::Folder.where(tool_id: tools.keys).where("file_folders.name LIKE ?", pattern).limit(PER_KIND)
      .map { |folder| hit(:folder, folder.name, folder, routes.tool_files_path(folder.tool_id, folder_id: folder.id)) }
  end

  def files
    Files::Item.where(tool_id: tools.keys).where("file_items.name LIKE ?", pattern).order(updated_at: :desc).limit(PER_KIND)
      .map { |file| hit(:file, file.name, file, routes.tool_files_item_path(file.tool_id, file)) }
  end

  def messages
    Chats::Message.joins(:chat, :rich_text_body)
      .where(chats: { tool_id: tools.keys }).where("action_text_rich_texts.body LIKE ?", pattern)
      .select("chat_messages.*, chats.tool_id AS found_in")
      .includes(:user, :rich_text_body).order(created_at: :desc).limit(PER_KIND)
      .select { |message| mentions?(message.body&.to_plain_text) }
      .map do |message|
        hit(:message, message.user&.name || "Someone", message,
          routes.tool_chat_path(message.found_in, anchor: ActionView::RecordIdentifier.dom_id(message)),
          excerpt_of(message.body&.to_plain_text))
      end
  end

  def events
    Calendars::Event.joins(calendar: :account)
      .where(calendar_accounts: { tool_id: tools.keys }).where("calendar_events.summary LIKE ?", pattern)
      .select("calendar_events.*, calendar_accounts.tool_id AS found_in")
      .order(starts_at: :desc).limit(PER_KIND)
      .map { |event| hit(:event, event.summary, event, routes.tool_calendar_path(event.found_in, week_start: event.starts_at.to_date.beginning_of_week.iso8601)) }
  end

  def mails
    Mails::Message.joins(:account)
      .where(mail_accounts: { tool_id: tools.keys }).not_trashed.not_draft
      .where("mail_messages.subject LIKE :q OR mail_messages.from_address LIKE :q", q: pattern)
      .select("mail_messages.*, mail_accounts.tool_id AS found_in")
      .order(sent_at: :desc).limit(PER_KIND)
      .map { |mail| hit(:mail, mail.subject.presence || "(no subject)", mail, routes.tool_mail_path(mail.found_in, mail), mail.from_address) }
  end

  def hit(kind, title, record, path, excerpt = nil)
    tool = tools[record.try(:found_in) || record.try(:tool_id)]
    Hit.new(kind: kind, title: title.to_s, excerpt: excerpt, tool: tool, path: path)
  end

  # Rich text is stored as HTML, so the query can match inside a tag ("href",
  # "strong") where nobody would see it. Only a match in the words counts.
  def mentions?(text)
    text.to_s.downcase.include?(query.downcase)
  end

  # The part of a long text around the first place the query appears
  def excerpt_of(text)
    text = text.to_s.squish
    index = text.downcase.index(query.downcase)
    return text.truncate(90) unless index

    start = [ index - 30, 0 ].max
    snippet = text[start, 90]
    "#{'…' if start.positive?}#{snippet}#{'…' if start + 90 < text.length}"
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
