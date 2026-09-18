# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :access_tokens, dependent: :destroy

  has_many :owned_tools, class_name: "Tool", foreign_key: :owner_id, dependent: :destroy
  # Runs before the dependent: :destroy above, so a tool someone else still owns
  # survives the account that created it.
  before_destroy :hand_over_co_owned_tools, prepend: true
  has_many :collaborations, class_name: "Collaborator", dependent: :destroy
  has_many :board_column_collapses, class_name: "Boards::ColumnCollapse", dependent: :delete_all
  has_many :sidebar_groups, -> { order(:position) }, class_name: "Sidebar::Group", dependent: :destroy

  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"

  NOTIFICATION_LIMIT = 100
  NOTIFICATION_DIGEST_OPTIONS = %w[off 1_hour 2_hours 4_hours daily].freeze

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true

  def name = "#{first_name} #{last_name}".strip

  # What an avatar falls back to, the same two letters the avatar partial draws
  def initials = "#{first_name.to_s.first}#{last_name.to_s.first}".upcase

  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }, allow_nil: true
  validates :notification_digest, inclusion: { in: NOTIFICATION_DIGEST_OPTIONS }
  validate :acceptable_avatar

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def prune_notifications!
    cutoff_id = notifications.order(created_at: :desc, id: :desc)
                             .offset(NOTIFICATION_LIMIT).limit(1).pick(:id)
    return unless cutoff_id

    notifications.where("id <= ?", cutoff_id).delete_all
  end

  def digest_interval
    case notification_digest
    when "1_hour"  then 1.hour
    when "2_hours" then 2.hours
    when "4_hours" then 4.hours
    when "daily"   then 1.day
    end
  end

  def accessible_tools
    Tool.joins(:collaborators).where(collaborators: { user_id: id }).distinct
  end

  # Accessible tools in this user's own sidebar order, which lives on their
  # collaborator record so it is theirs alone.
  def sidebar_tools
    Tool.joins(:collaborators).where(collaborators: { user_id: id })
        .order(Collaborator.arel_table[:sidebar_position].asc, Tool.arel_table[:id].asc)
  end

  def ungrouped_tools
    grouped_ids = sidebar_groups.joins(:memberships).pluck("sidebar_memberships.tool_id")
    scope = sidebar_tools.includes(:tool_type, :mail_account)
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

  def hand_over_co_owned_tools
    owned_tools.find_each do |tool|
      successor = tool.collaborators.owners.where.not(user_id: id).order(:created_at, :id).first
      tool.update_column(:owner_id, successor.user_id) if successor
    end
  end

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
