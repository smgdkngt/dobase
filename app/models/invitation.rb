# frozen_string_literal: true

class Invitation < ApplicationRecord
  STATUSES = %w[pending accepted declined].freeze

  belongs_to :tool
  belongs_to :invited_by, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :expires_at, presence: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :not_expired, -> { where("expires_at > ?", Time.current) }
  scope :active, -> { pending.not_expired }
  scope :declined, -> { where(status: "declined") }

  validate :cannot_invite_existing_member

  def expired?
    expires_at < Time.current
  end

  def pending?
    status == "pending"
  end

  def acceptable?
    pending? && !expired?
  end

  def accept!(user)
    transaction do
      update!(status: "accepted", accepted_at: Time.current)
      tool.collaborators.create!(user: user, role: "collaborator")
    end
  end

  def decline!
    update!(status: "declined")
  end

  def declined?
    status == "declined"
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiry
    self.expires_at ||= 7.days.from_now
  end

  def cannot_invite_existing_member
    return unless tool
    if tool.collaborators.joins(:user).exists?(users: { email_address: email })
      errors.add(:email, "is already a member of this tool")
    end
  end
end
