# frozen_string_literal: true

module EncryptedPassword
  extend ActiveSupport::Concern

  SYNC_STATUSES = %w[pending syncing synced error].freeze
  # How long the scheduled sync leaves an account alone after its server turned the login down
  LOGIN_RETRY = 1.hour

  included do
    validates :sync_status, inclusion: { in: SYNC_STATUSES }

    scope :synced, -> { where(sync_status: "synced") }
    scope :needs_sync, -> { where(sync_status: %w[pending error]) }
  end

  def password
    return nil if encrypted_password.blank?
    encryptor.decrypt_and_verify(encrypted_password)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    begin
      plain = legacy_encryptor.decrypt_and_verify(encrypted_password)
      update_column(:encrypted_password, encryptor.encrypt_and_sign(plain))
      plain
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end
  end

  def password=(new_password)
    return if new_password.blank?
    self.encrypted_password = encryptor.encrypt_and_sign(new_password)
  end

  def synced?
    sync_status == "synced"
  end

  def syncing?
    sync_status == "syncing"
  end

  def sync_error?
    sync_status == "error"
  end

  def mark_syncing!
    update!(sync_status: "syncing", sync_error: nil)
  end

  def mark_synced!
    update!(sync_status: "synced", last_synced_at: Time.current, sync_error: nil)
  end

  # When it went wrong, also when it went wrong the same way as before (waiting_after_refused_login?)
  def mark_sync_error!(message)
    update!(sync_status: "error", sync_error: message, updated_at: Time.current)
  end

  # Trying the same credentials every few minutes could get an account locked, so after a
  # login that was turned down the scheduled sync waits. Not for good: a server can turn a
  # good login down for a moment (iCloud does), and then nobody would hear of new mail
  # until someone asked for a sync by hand.
  def waiting_after_refused_login?
    authentication_failed? && updated_at > LOGIN_RETRY.ago
  end

  private

  def encryptor
    key = ActiveSupport::KeyGenerator.new(
      Rails.application.secret_key_base
    ).generate_key(encryption_salt, 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def legacy_encryptor
    key = Rails.application.secret_key_base[0, 32]
    ActiveSupport::MessageEncryptor.new(key)
  end

  # Override in including class to provide a unique salt
  def encryption_salt
    raise NotImplementedError, "#{self.class} must define #encryption_salt"
  end
end
