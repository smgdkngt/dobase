# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  has_many :owned_tools, class_name: "Tool", foreign_key: :owner_id, dependent: :destroy
  has_many :collaborations, class_name: "Collaborator", dependent: :destroy
  has_many :sidebar_groups, -> { order(:position) }, class_name: "Sidebar::Group", dependent: :destroy

  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"

  NOTIFICATION_LIMIT = 100

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true

  def name = "#{first_name} #{last_name}".strip
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }, allow_nil: true
  validate :acceptable_avatar

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def prune_notifications!
    cutoff_id = notifications.order(created_at: :desc, id: :desc)
                             .offset(NOTIFICATION_LIMIT).limit(1).pick(:id)
    return unless cutoff_id

    notifications.where("id <= ?", cutoff_id).delete_all
  end

  def accessible_tools
    Tool.joins(:collaborators).where(collaborators: { user_id: id }).distinct
  end

  def ungrouped_tools
    grouped_ids = sidebar_groups.joins(:memberships).pluck("sidebar_memberships.tool_id")
    scope = accessible_tools.includes(:tool_type, :mail_account).order(:sidebar_position)
    grouped_ids.any? ? scope.where.not(id: grouped_ids) : scope
  end

  # --- Two-factor authentication ---

  RECOVERY_CODE_COUNT = 8

  def otp
    ROTP::TOTP.new(otp_secret, issuer: Rails.application.config.x.app.name)
  end

  def otp_provisioning_uri
    otp.provisioning_uri(email_address)
  end

  def verify_otp(code)
    return false if otp_secret.blank?

    otp.verify(code.to_s.delete(" "), drift_behind: 15, drift_ahead: 15).present?
  end

  def verify_recovery_code(code)
    return false if otp_recovery_codes.blank?

    codes = JSON.parse(otp_recovery_codes)
    match_index = codes.index { |hashed| BCrypt::Password.new(hashed) == code.to_s.strip.downcase }
    return false unless match_index

    codes.delete_at(match_index)
    update_column(:otp_recovery_codes, codes.to_json)
    true
  end

  def generate_recovery_codes
    plain_codes = RECOVERY_CODE_COUNT.times.map { SecureRandom.hex(4) }
    hashed = plain_codes.map { |c| BCrypt::Password.create(c).to_s }
    update_column(:otp_recovery_codes, hashed.to_json)
    plain_codes
  end

  private

  def acceptable_avatar
    return unless avatar.attached?
    unless avatar.content_type.in?(%w[image/png image/jpeg image/gif image/webp])
      errors.add(:avatar, "must be an image (PNG, JPEG, GIF, or WebP)")
    end
    if avatar.byte_size > 5.megabytes
      errors.add(:avatar, "must be less than 5MB")
    end
  end
end
