# frozen_string_literal: true

class Collaborator < ApplicationRecord
  ROLES = %w[owner collaborator].freeze

  belongs_to :tool
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :tool_id, message: "is already a collaborator" }

  after_destroy :delete_tool_notifications

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

  # Notifications render the tool's current card, todo and file names, so
  # someone who leaves or is removed would keep seeing them. Clear theirs out.
  def delete_tool_notifications
    user.notifications.where(event: tool.notification_events).delete_all
  end
end
