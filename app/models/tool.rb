# frozen_string_literal: true

class Tool < ApplicationRecord
  belongs_to :tool_type
  belongs_to :owner, class_name: "User"
  has_many :collaborators, dependent: :destroy
  has_many :users, through: :collaborators
  has_many :invitations, dependent: :destroy
  has_one :mail_account, class_name: "Mails::Account", dependent: :destroy
  has_one :calendar_account, class_name: "Calendars::Account", dependent: :destroy
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
