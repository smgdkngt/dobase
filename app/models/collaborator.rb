# frozen_string_literal: true

class Collaborator < ApplicationRecord
  ROLES = %w[owner collaborator].freeze

  belongs_to :tool
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :tool_id, message: "is already a collaborator" }

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
end
