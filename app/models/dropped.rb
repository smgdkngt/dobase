# frozen_string_literal: true

# Something dragged from one place in Dobase and dropped on another (drag_drop_controller.js):
# a mail on a board makes a card, a card in a chat a message, a file on a todo list a todo
# with the file. The page names what is dragged by a signed GlobalID, so it can't name
# what its reader may not see, and it is checked again against whoever dropped it.
#
# The place it is dropped makes what it makes the way it always does (a card is made by
# Columns::CardsController#create), taking its title, text and files from here: a link
# back to what was dropped, a few words of it, and its files, which share their stored
# file with the original (Rails won't purge a blob that is still attached elsewhere).
class Dropped
  PURPOSE = "drag"
  KINDS = {
    "Mails::Message" => "mail", "Boards::Card" => "card", "Todos::Item" => "todo", "Files::Item" => "file",
    "Docs::Document" => "document", "Chats::Message" => "message", "Calendars::Event" => "event"
  }.freeze
  # How much of what was dropped comes along as text
  EXCERPT = 280

  include Rails.application.routes.url_helpers

  def self.sgid_for(record)
    record.to_sgid(for: PURPOSE, expires_in: 1.day).to_s
  end

  # What `sgid` names, when `user` may see it; nil otherwise
  def self.find(sgid, user:)
    record = GlobalID::Locator.locate_signed(sgid.to_s, for: PURPOSE) if sgid.present?
    return unless record && KINDS.key?(record.class.name)

    dropped = new(record)
    dropped if dropped.tool&.accessible_by?(user)
  end

  attr_reader :record

  def initialize(record, tool: nil)
    @record = record
    @tool = tool
  end

  def kind
    KINDS.fetch(record.class.name)
  end

  def tool
    @tool ||= case record
    when Mails::Message then record.account.tool
    when Boards::Card then record.column.board.tool
    when Todos::Item then record.list.tool
    when Files::Item, Docs::Document then record.tool
    when Chats::Message then record.chat.tool
    when Calendars::Event then record.calendar.account.tool
    end
  end

  def title
    text = case record
    when Mails::Message then record.subject.presence || "(No subject)"
    when Boards::Card, Todos::Item, Docs::Document then record.title
    when Files::Item then record.name
    when Chats::Message then record.body.to_plain_text.squish.truncate(80)
    when Calendars::Event then record.summary
    end
    text.presence || kind.capitalize
  end

  def path
    case record
    when Mails::Message then tool_mail_path(tool, record)
    when Boards::Card then tool_board_path(tool, card: record.id)
    when Todos::Item then tool_todo_path(tool, item: record.id)
    when Files::Item then tool_files_item_path(tool, record)
    when Docs::Document then tool_docs_document_path(tool, record)
    when Chats::Message then tool_chat_path(tool, anchor: ActionView::RecordIdentifier.dom_id(record))
    when Calendars::Event then tool_calendar_event_path(tool, record)
    end
  end

  # A few words of it, as plain text: what a mail or a message says, a card's description
  def excerpt
    text = case record
    when Mails::Message then record.body_plain.presence || ActionController::Base.helpers.strip_tags(record.body_html.to_s)
    when Boards::Card, Todos::Item then record.description.to_plain_text
    when Docs::Document then record.content.to_plain_text
    when Chats::Message then record.body.to_plain_text
    when Calendars::Event then [ record.location, record.description ].compact_blank.join("\n")
    end
    text.to_s.squish.truncate(EXCERPT, separator: " ").presence
  end

  # Who it is from and when, where that says something
  def byline
    case record
    when Mails::Message then [ record.from_name.presence || record.from_address, record.sent_at&.to_date&.to_fs(:long) ].compact.join(", ")
    when Chats::Message then record.user&.name
    when Calendars::Event then record.starts_at&.to_fs(:long)
    end.presence
  end

  # The text a card, a todo or a chat message made of it starts with: a link back
  # to it by its title, then who and when, then a few of its words
  def html(base_url)
    helpers = ActionController::Base.helpers
    link = helpers.link_to(title, "#{base_url}#{path}")
    lines = [ helpers.tag.p { helpers.safe_join([ link, (" — #{byline}" if byline) ].compact) } ]
    lines << helpers.tag.blockquote(excerpt) if excerpt && !record.is_a?(Chats::Message)
    lines << helpers.tag.p(excerpt) if excerpt && record.is_a?(Chats::Message)
    helpers.safe_join(lines)
  end

  # The stored files that come along
  def blobs
    case record
    when Mails::Message then record.attachments.filter_map { |attachment| attachment.file.blob if attachment.file.attached? }
    when Boards::Card, Todos::Item then record.attachments.filter_map { |attachment| attachment.file.blob if attachment.file.attached? }
    when Files::Item then [ record.file.blob ].compact
    when Chats::Message then record.files.blobs.to_a
    else []
    end
  end
end
