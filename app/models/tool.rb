# frozen_string_literal: true

class Tool < ApplicationRecord
  belongs_to :tool_type
  belongs_to :owner, class_name: "User"
  has_many :collaborators, dependent: :destroy
  has_many :users, through: :collaborators
  has_many :invitations, dependent: :destroy
  has_one :mail_account, class_name: "Mails::Account", dependent: :destroy
  has_one :calendar_account, class_name: "Calendars::Account", dependent: :destroy
  has_many :calendars, class_name: "Calendars::Calendar", dependent: :destroy
  has_one :board, class_name: "Boards::Board", dependent: :destroy
  has_one :chat, class_name: "Chats::Chat", dependent: :destroy
  has_many :sidebar_memberships, class_name: "Sidebar::Membership", dependent: :destroy
  has_many :file_folders, class_name: "Files::Folder", dependent: :destroy
  has_many :file_items, class_name: "Files::Item", dependent: :destroy
  has_many :documents, class_name: "Docs::Document", dependent: :destroy
  has_one :room, class_name: "Rooms::Room", dependent: :destroy
  has_many :todo_lists, class_name: "Todos::List", dependent: :destroy

  validates :name, presence: true

  before_destroy :cleanup_notifications

  after_create :add_creator_as_owner
  after_create :create_default_board, if: :boards_tool?
  after_create :create_default_chat, if: :chat_tool?
  after_create :create_default_room, if: :room_tool?
  after_create :create_default_todo_list, if: :todos_tool?

  def owned_by?(user)
    collaborators.exists?(user_id: user.id, role: "owner")
  end

  def accessible_by?(user)
    collaborators.exists?(user_id: user.id)
  end

  # Matches emoji at the start of the name (including compound emoji with ZWJ, skin tones, variation selectors)
  LEADING_EMOJI_REGEX = /\A(\p{Extended_Pictographic}[\u{FE0F}\u{200D}\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Emoji_Component}]*)\s*/

  def emoji_icon
    match = name&.match(LEADING_EMOJI_REGEX)
    match&.[](1)
  end

  def display_name
    emoji_icon ? name.sub(LEADING_EMOJI_REGEX, "") : name
  end

  def display_icon
    emoji_icon ? nil : tool_type.icon
  end

  # Returns a Set of tool IDs that have activity since the user last visited.
  # Skips mail (has its own unread badge) and room (no async content).
  def self.unread_tool_ids_for(user)
    collabs = Collaborator.where(user_id: user.id).pluck(:tool_id, :last_seen_at).to_h
    tool_ids = collabs.keys
    return Set.new if tool_ids.empty?

    # Exclude mail and room tools
    skip_slugs = %w[mail room]
    skip_ids = Tool.where(id: tool_ids).joins(:tool_type).where(tool_types: { slug: skip_slugs }).pluck(:id)
    candidate_ids = tool_ids - skip_ids
    return Set.new if candidate_ids.empty?

    unread = Set.new

    # Chat messages
    Chats::Chat.where(tool_id: candidate_ids)
      .joins(:messages)
      .group(:tool_id)
      .maximum("chat_messages.created_at")
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    # Board cards (cards → columns → boards)
    Boards::Board.where(tool_id: candidate_ids)
      .joins(columns: :cards)
      .group("boards.tool_id")
      .maximum("cards.created_at")
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    # Documents
    Docs::Document.where(tool_id: candidate_ids)
      .group(:tool_id)
      .maximum(:updated_at)
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    # Files
    Files::Item.where(tool_id: candidate_ids)
      .group(:tool_id)
      .maximum(:created_at)
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    # Todos
    Todos::Item.joins(:list)
      .where(todo_lists: { tool_id: candidate_ids })
      .group("todo_lists.tool_id")
      .maximum("todo_items.updated_at")
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    # Calendar events (events → calendars → tool)
    Calendars::Event
      .joins(:calendar)
      .where(calendar_calendars: { tool_id: candidate_ids })
      .group("calendar_calendars.tool_id")
      .maximum("calendar_events.updated_at")
      .each do |tid, max_at|
        ts = collabs[tid]
        unread << tid if max_at && (ts.nil? || max_at > ts)
      end

    unread
  end

  private

  def boards_tool?
    tool_type.slug == "boards"
  end

  def chat_tool?
    tool_type.slug == "chat"
  end

  def room_tool?
    tool_type.slug == "room"
  end

  def todos_tool?
    tool_type.slug == "todos"
  end

  def cleanup_notifications
    gid = to_global_id.to_s
    event_ids = Noticed::Event.where("json_extract(params, '$.tool._aj_globalid') = ?", gid).pluck(:id)
    return if event_ids.empty?

    Noticed::Notification.where(event_id: event_ids).delete_all
    Noticed::Event.where(id: event_ids).delete_all
  end

  def add_creator_as_owner
    collaborators.create!(user: owner, role: "owner")
  end

  def create_default_board
    Boards::Board.create_default_for(self)
  end

  def create_default_chat
    Chats::Chat.create!(tool: self)
  end

  def create_default_room
    Rooms::Room.create!(tool: self)
  end

  def create_default_todo_list
    Todos::List.create_default_for(self)
  end
end
