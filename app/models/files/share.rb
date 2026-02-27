# frozen_string_literal: true

module Files
  class Share < ApplicationRecord
    self.table_name = "file_shares"

    has_secure_password validations: false

    belongs_to :shareable, polymorphic: true
    belongs_to :created_by, class_name: "User"

    validates :token, presence: true, uniqueness: true

    before_validation :generate_token, on: :create

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def active?
      !expired?
    end

    def password_protected?
      password_digest.present?
    end

    def increment_download!
      increment!(:download_count)
    end

    def tool
      case shareable
      when Files::Item then shareable.tool
      when Files::Folder then shareable.tool
      end
    end

    def folder?
      shareable_type == "Files::Folder"
    end

    def file?
      shareable_type == "Files::Item"
    end

    private

    def generate_token
      self.token = SecureRandom.urlsafe_base64(32)
    end
  end
end
