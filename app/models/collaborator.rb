# frozen_string_literal: true

class Collaborator < ApplicationRecord
  ROLES = %w[owner collaborator].freeze

  belongs_to :tool
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :tool_id, message: "is already a collaborator" }

  before_create :place_last_in_sidebar

  after_destroy :delete_tool_notifications
  after_destroy :unassign_tool_work
  after_destroy :hand_over_tool

  scope :owners, -> { where(role: "owner") }
  scope :muted, -> { where.not(muted_at: nil) }
  scope :unmuted, -> { where(muted_at: nil) }

  def muted? = muted_at.present?

  def mute!
    update!(muted_at: Time.current)
  end

  def unmute!
    update!(muted_at: nil)
  end

  def touch_last_seen!
    update_column(:last_seen_at, Time.current)
  end

  private

  # The sidebar order is per person, so a tool you gain access to lands at the
  # bottom of your own sidebar and leaves everybody else's alone.
  def place_last_in_sidebar
    self.sidebar_position = (user.collaborations.maximum(:sidebar_position) || -1) + 1
  end

  # tools.owner_id names the account a tool falls to when it is deleted. Someone
  # who leaves or is removed shouldn't take the tool down with them later, so
  # hand it to whoever still owns it.
  def hand_over_tool
    return if destroyed_by_association || tool.owner_id != user_id

    successor = tool.collaborators.owners.where.not(user_id: user_id).order(:created_at, :id).first
    tool.update_column(:owner_id, successor.user_id) if successor
  end

  # Someone who leaves or is removed can't open what they were assigned, can't be
  # picked from the assignee menus any more and doesn't show up in the assignee
  # filter, so their name would sit on todos and cards nobody can hand on. Give
  # that work back to the tool.
  def unassign_tool_work
    Todos::Item.joins(:list)
      .where(todo_lists: { tool_id: tool_id }, assigned_user_id: user_id)
      .update_all(assigned_user_id: nil)

    Boards::Card.joins(column: :board)
      .where(boards: { tool_id: tool_id }, assigned_user_id: user_id)
      .update_all(assigned_user_id: nil)
  end

  # Notifications render the tool's current card, todo and file names, so
  # someone who leaves or is removed would keep seeing them. Clear theirs out.
  def delete_tool_notifications
    user.notifications.where(event: tool.notification_events).delete_all
  end
end
