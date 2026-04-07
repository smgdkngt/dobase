# frozen_string_literal: true

module Mails
  class Account < ApplicationRecord
    include EncryptedPassword

    self.table_name = "mail_accounts"

    belongs_to :tool
    has_many :messages, class_name: "Mails::Message", foreign_key: "mail_account_id", dependent: :destroy
    has_many :labels, class_name: "Mails::Label", foreign_key: "mail_account_id", dependent: :destroy
    has_many :contacts, class_name: "Mails::Contact", foreign_key: "mail_account_id", dependent: :destroy

    validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :imap_host, presence: true
    validates :smtp_host, presence: true
    validates :username, presence: true
    validates :encrypted_password, presence: true

    SMTP_AUTH_METHODS = %w[plain login cram_md5].freeze

    validates :smtp_auth, inclusion: { in: SMTP_AUTH_METHODS }

    BUILT_IN_FOLDERS = %w[INBOX Sent Drafts Trash Spam INBOX.spam INBOX.Spam Junk].freeze

    def custom_folders
      return [] if synced_folders.blank?
      excluded = BUILT_IN_FOLDERS + [ archive_folder.presence ].compact
      JSON.parse(synced_folders).reject { |f| f.in?(excluded) }
    rescue JSON::ParserError
      []
    end

    def record_contact(email, name = nil)
      contact = contacts.find_or_initialize_by(email_address: email.downcase.strip)
      contact.name = name if name.present?
      contact.times_contacted = (contact.times_contacted || 0) + 1
      contact.last_contacted_at = Time.current
      contact.save!
      contact
    end

    private

    def encryption_salt
      "mail account password"
    end
  end
end
