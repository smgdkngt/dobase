# frozen_string_literal: true

module Mails
  class Account < ApplicationRecord
    include EncryptedPassword

    self.table_name = "mail_accounts"

    belongs_to :tool
    has_many :messages, class_name: "Mails::Message", foreign_key: "mail_account_id", dependent: :destroy
    has_many :attachments, through: :messages
    has_many :contacts, class_name: "Mails::Contact", foreign_key: "mail_account_id", dependent: :destroy
    has_many :trusted_senders, class_name: "Mails::TrustedSender", foreign_key: "mail_account_id", dependent: :delete_all

    validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
    validates :imap_host, presence: true
    validates :smtp_host, presence: true
    validates :username, presence: true
    validates :encrypted_password, presence: true

    SMTP_AUTH_METHODS = %w[plain login cram_md5].freeze

    validates :smtp_auth, inclusion: { in: SMTP_AUTH_METHODS }

    AUTHENTICATION_FAILED = "The mail server didn't accept the username or password"
    # Changing these is worth another try after the server turned the login down
    CONNECTION_SETTINGS = %w[imap_host imap_port imap_ssl username encrypted_password].freeze

    BUILT_IN_FOLDERS = %w[INBOX Sent Drafts Trash Spam INBOX.spam INBOX.Spam Junk].freeze
    # The server's trash, whatever the server calls it ("Deleted Messages", "[Gmail]/Trash", ...)
    TRASH = "Trash"

    # Images load straight away in mail from a trusted sender, and in your own
    def shows_images_from?(address)
      return false if address.blank?
      address.casecmp?(email_address) || trusted_senders.exists?(email_address: address)
    end

    def custom_folders
      return [] if synced_folders.blank?
      excluded = BUILT_IN_FOLDERS + [ archive_folder.presence ].compact
      JSON.parse(synced_folders).reject { |f| f.in?(excluded) }
    rescue JSON::ParserError
      []
    end

    # The folder to move mail to, by the name the server has for it: the inbox, sent mail or
    # one of the account's own folders. Nil for a folder the server doesn't have.
    def folder_to_move_to(name)
      folders = [ "INBOX", "Sent", *custom_folders ]
      folders.find { |folder| folder == name.to_s } || folders.find { |folder| folder == name.to_s.strip }
    end

    # The folders synced besides the inbox and sent mail: the account's own, and the archive
    # and trash, where other mail programs archive and delete to as well
    def other_folders_to_sync
      [ *custom_folders, archive_folder.presence, TRASH ].compact.uniq.select { |folder| folder.in?(server_folders) }
    end

    def server_folders
      JSON.parse(synced_folders.presence || "[]")
    rescue JSON::ParserError
      []
    end

    def server_trash?
      TRASH.in?(server_folders)
    end

    # Archived mail as the Archive lists it: mail archived here, and the mail in the server's
    # archive folder, where other mail programs archive to (and where the sync finds the mail
    # archived here once the server has moved it)
    def archived_messages
      archived = messages.not_trashed.not_draft.where(archived: true)
      archive_folder.present? ? archived.or(messages.not_trashed.not_draft.where(folder: archive_folder)) : archived
    end

    def in_archive_folder?(message)
      archive_folder.present? && message.folder == archive_folder
    end

    # Mail archived here keeps the folder it was archived from and the UID it had there, while
    # the server has it in the archive folder under another UID. There it's found by its Message-ID.
    def archived_on_server?(message)
      archive_folder.present? && message.archived? && message.folder != archive_folder
    end

    # Trashed mail goes to the server's trash, as in other mail programs, so it can be restored
    # there too. A server without a trash deletes it, and it's only kept here for 30 days.
    def trash(messages)
      messages = messages.reject(&:trashed?)
      on_server = uids_by_folder(messages)
      archived = messages.select { |message| archived_on_server?(message) }

      if server_trash?
        messages.each(&:move_to_trash!)
        on_server.each { |folder, uids| ImapSyncJob.perform_later(id, "move_to_folder", uids, folder, TRASH) }
        archived.each { |message| ImapSyncJob.perform_later(id, "move_to_folder_by_message_id", nil, archive_folder, TRASH, message.message_id) }
      else
        messages.each { |message| message.update!(trashed: true, archived: false) }
        on_server.each { |folder, uids| ImapSyncJob.perform_later(id, "delete_message", uids, folder) }
        archived.each { |message| ImapSyncJob.perform_later(id, "delete_message_by_message_id", nil, archive_folder, message.message_id) }
      end
      messages
    end

    # Mail in the server's trash goes back to the inbox, a draft to the drafts. Mail deleted
    # on the server before (it had no trash) can only come back here.
    def restore(messages)
      messages.select(&:trashed?).each do |message|
        if message.folder == TRASH
          folder = message.draft? ? "Drafts" : "INBOX"
          # The trash gave it a new UID, so it's found by its Message-ID; the inbox's next sync gives it its UID there
          ImapSyncJob.perform_later(id, "move_to_folder_by_message_id", nil, TRASH, folder, message.message_id)
          message.move_to_folder!(folder, on_server: false)
        else
          # Its UID went with it on the server: with that UID the folder's next sync would take
          # it for mail gone from the folder, and remove it. A server that still has it gives it its UID again.
          message.update!(trashed: false, uid: nil)
        end
      end
    end

    def delete_for_good(messages)
      messages = messages.select(&:trashed?)
      uids_by_folder(messages).each { |folder, uids| ImapSyncJob.perform_later(id, "delete_message", uids, folder) }
      # Just trashed, and not synced since: found in the server's trash by its Message-ID
      messages.select { |message| message.folder == TRASH && message.uid.blank? }.each do |message|
        ImapSyncJob.perform_later(id, "delete_message_by_message_id", nil, TRASH, message.message_id)
      end
      messages.each(&:destroy)
    end

    # Syncing again with the same credentials only gets turned down again, so the scheduled
    # sync skips the account until its settings change or someone asks for a sync
    def authentication_failed?
      sync_error? && sync_error == AUTHENTICATION_FAILED
    end

    # The installed app's icon counts unread mail, on every page each of the tool's people has open
    def broadcast_unread_mail
      tool.users.each do |user|
        ActionCable.server.broadcast("notifications:#{user.id}", { type: "unread_mail", count: user.unread_mail_count })
      end
    end

    # A draft written from here: it's saved in the server's Drafts folder by SyncDraftJob
    def new_draft(**attributes)
      messages.new(draft: true, message_id: "<draft-#{SecureRandom.uuid}@local>", folder: "Drafts",
        from_address: email_address, from_name: display_name, read: true, sent_at: Time.current, **attributes)
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

    def uids_by_folder(messages)
      messages.select { |message| message.uid.present? }.group_by { |message| message.folder || "INBOX" }.transform_values { |in_folder| in_folder.map(&:uid) }
    end

    def encryption_salt
      "mail account password"
    end
  end
end
