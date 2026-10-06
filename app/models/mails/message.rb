# frozen_string_literal: true

module Mails
  class Message < ApplicationRecord
    self.table_name = "mail_messages"

    belongs_to :account, class_name: "Mails::Account", foreign_key: "mail_account_id"
    has_many :attachments, class_name: "Mails::Attachment", foreign_key: "mail_message_id", inverse_of: :message, dependent: :destroy
    has_many :calendar_invites, class_name: "Calendars::Invite", foreign_key: "mail_message_id", dependent: :destroy
    # The mail a draft answers or forwards, added below its text when it goes out (Mails::Quote)
    belongs_to :quoted_message, class_name: "Mails::Message", optional: true

    CONTENT_ID_URL = /\bcid:[^"'\s)>]+/i
    INLINE_IMAGE_MAX_SIZE = 5.megabytes

    validates :message_id, presence: true, uniqueness: { scope: %i[mail_account_id folder] }

    # When a message went to the trash: the trash is emptied of messages older than 30 days
    before_save -> { self.trashed_at = trashed? ? Time.current : nil }, if: :trashed_changed?

    scope :trashed, -> { where(trashed: true) }
    scope :not_trashed, -> { where(trashed: false) }
    scope :archived, -> { where(archived: true) }
    scope :not_archived, -> { where(archived: false) }
    scope :with_attachments, -> { where(has_attachments: true) }

    scope :search, ->(query) {
      where(
        "subject LIKE :q OR from_address LIKE :q OR body_plain LIKE :q",
        q: "%#{query}%"
      )
    }

    scope :not_draft, -> { where(draft: false) }
    scope :inbox, -> { where(folder: "INBOX").not_trashed.not_draft }
    scope :sent, -> { where(folder: "Sent").not_trashed.not_draft }
    scope :drafts, -> { where(draft: true).not_trashed }
    scope :unread, -> { where(read: false) }
    scope :starred, -> { where(starred: true).not_trashed.not_draft }

    scope :in_thread, ->(thread_id) { where(thread_id: thread_id).order(sent_at: :asc) }

    before_save :set_thread_id

    def to_addresses_list
      return [] if to_addresses.blank?
      JSON.parse(to_addresses)
    rescue JSON::ParserError
      []
    end

    def to_addresses_list=(list)
      self.to_addresses = list.to_json
    end

    def cc_addresses_list
      return [] if cc_addresses.blank?
      JSON.parse(cc_addresses)
    rescue JSON::ParserError
      []
    end

    def cc_addresses_list=(list)
      self.cc_addresses = list.to_json
    end

    # Only drafts have a Bcc: mail that came in doesn't show one
    def bcc_addresses_list
      return [] if bcc_addresses.blank?
      JSON.parse(bcc_addresses)
    rescue JSON::ParserError
      []
    end

    # Attachments of other mail, like the one a draft forwards. The copies share the
    # stored file with the original.
    def copy_attachments(originals)
      originals.each do |original|
        next unless original.file.attached?

        attachments.build(original.slice(:filename, :content_type, :file_size)).file.attach(original.file.blob)
      end
      self.has_attachments = attachments.any?
    end

    # Files uploaded with the compose form
    def attach_uploads(files)
      files.each do |file|
        attachments.build(filename: file.original_filename, content_type: file.content_type, file_size: file.size).file.attach(file)
      end
      self.has_attachments = attachments.any?
    end

    def body
      body_html.presence || body_plain
    end

    # The text part, or the text of the HTML part for HTML-only messages. Drafts
    # are written as HTML and their text part is a copy of it, so they use the HTML.
    def plain_text_body
      if body_html.present? && (body_plain.blank? || draft?)
        PlainText.from_html(body_html)
      else
        body_plain.to_s
      end
    end

    def display_from
      from_name.presence || from_address
    end

    def preview
      return "" if body_plain.blank?
      body_plain.gsub(/\s+/, " ").strip.truncate(120)
    end

    # The attachments the HTML shows as pictures (<img src="cid:...">), by the ID it uses
    def inline_images
      @inline_images ||= body_html.to_s.scan(CONTENT_ID_URL).map { |url| content_id_of(url) }.uniq.filter_map do |id|
        image = attachments.find { |attachment| attachment.content_id?(id) }
        [ id, image ] if image&.file&.attached? && image.file_size.to_i <= INLINE_IMAGE_MAX_SIZE
      end.to_h
    end

    # The rest are listed below the message
    def listed_attachments
      attachments.to_a - inline_images.values
    end

    # The HTML with its pictures in it, so they show without loading anything
    def body_html_with_inline_images
      data_urls = inline_images.filter_map do |id, image|
        [ id, "data:#{image.content_type};base64,#{Base64.strict_encode64(image.file.download)}" ]
      rescue ActiveStorage::FileNotFoundError
        # A picture whose file is gone from storage is left out; the message still opens
        Rails.logger.warn("Inline image #{image.id} of mail #{self.id} has no file in storage")
        nil
      end.to_h

      body_html.to_s.gsub(CONTENT_ID_URL) { |url| data_urls.fetch(content_id_of(url), url) }
    end

    # The HTML with each picture's cid: link as the block gives it
    def body_html_with_image_urls
      body_html.to_s.gsub(CONTENT_ID_URL) { |url| (image = inline_images[content_id_of(url)]) ? yield(image) : url }
    end

    # The text written here, then the mail it answers or forwards, as it goes out
    def outgoing_html
      [ body_html, Quote.of(self)&.to_html ].compact.join
    end

    # A draft that is sent off: out of Drafts and into Sent from that moment, where its
    # conversation shows it, under the Message-ID it goes out with. SendMailJob sends it.
    def start_sending!
      ImapSyncJob.perform_later(account.id, "delete_draft", uid, "Drafts") if uid
      # Mail that starts a conversation is its thread
      self.thread_id = nil if thread_id == message_id
      update!(draft: false, sending: true, folder: "Sent", uid: nil, message_id: "#{SecureRandom.uuid}@#{account.smtp_host}")
    end

    # The mail server didn't take it: a draft again, to change or send once more
    def back_to_drafts!
      update!(draft: true, sending: false, folder: "Drafts", trashed: false, archived: false)
    end

    def mark_as_read!
      update!(read: true)
      sync_read_flag_to_imap(true)
      account.broadcast_unread_mail
    end

    def mark_as_unread!
      update!(read: false)
      sync_read_flag_to_imap(false)
      account.broadcast_unread_mail
    end

    def toggle_starred!
      update!(starred: !starred)
      sync_starred_flag_to_imap
    end

    def toggle_read!
      update!(read: !read)
      sync_read_flag_to_imap(read)
    end

    def conversation
      return account.messages.where(id: id) if thread_id.blank?
      account.messages.in_thread(thread_id)
    end

    # The conversation as it reads: a message that is in several folders on the
    # server once, this message's copy for its own
    def conversation_without_copies(scope = conversation)
      messages = scope.to_a
      kept = messages.group_by(&:message_id).values.map { |copies| copies.find { |copy| copy == self } || copies.first }
      messages & kept
    end

    # Moving to a folder that already has a copy of the message leaves one copy there.
    # On the server the message gets a new UID in its new folder, and the next sync of that
    # folder finds it by its Message-ID. Until then it has no UID: with the old one that sync
    # would take it for mail gone from the folder, and remove it.
    def move_to_folder!(target_folder, on_server: true)
      source_folder, source_uid = folder || "INBOX", uid
      in_archive = account.archived_on_server?(self)
      account.messages.where(folder: target_folder, message_id: message_id).where.not(id: id).destroy_all
      update!(folder: target_folder, archived: false, trashed: false, uid: nil)
      return unless on_server

      ImapSyncJob.perform_later(account.id, "move_to_folder", source_uid, source_folder, target_folder) if source_uid
      # Archived here, the server has it in the archive folder, under another UID
      ImapSyncJob.perform_later(account.id, "move_to_folder_by_message_id", nil, account.archive_folder, target_folder, message_id) if in_archive
    end

    # Into the server's trash, where Mails::Account#trash moves it on the server
    def move_to_trash!
      account.messages.where(folder: Account::TRASH, message_id: message_id).where.not(id: id).destroy_all
      update!(folder: Account::TRASH, trashed: true, archived: false, uid: nil)
    end

    def conversation_count
      conversation.count
    end

    def conversation_unread_count
      conversation.unread.count
    end

    def conversation_participants
      conversation.pluck(:from_address).uniq
    end

    def normalized_subject
      subject.to_s.gsub(/^(Re|Fwd|Fw):\s*/i, "").strip
    end

    # The References of a reply to this message: the messages before it, then this one (RFC 5322, 3.6.4)
    def reply_references
      [ references.presence || in_reply_to, message_id ].compact_blank.join(" ")
    end

    private

    def content_id_of(url)
      CGI.unescapeURIComponent(url[4..]).downcase
    end

    def sync_read_flag_to_imap(is_read)
      return unless uid.present? && account.present?
      ImapSyncJob.perform_later(account.id, "mark_as_#{is_read ? 'read' : 'unread'}", uid, folder || "INBOX")
    end

    def sync_starred_flag_to_imap
      return unless uid.present? && account.present?
      ImapSyncJob.perform_later(account.id, "set_starred", uid, folder || "INBOX", starred)
    end

    def set_thread_id
      return if thread_id.present?

      # Try in_reply_to parent first
      if in_reply_to.present?
        parent = account.messages.find_by(message_id: in_reply_to)
        if parent&.thread_id.present?
          self.thread_id = parent.thread_id
          return
        end
      end

      # Check references chain (first match wins, first ref is the thread root)
      if self.references.present?
        ref_ids = self.references.to_s.split(/\s+/)
        ref_ids.each do |ref_id|
          parent = account.messages.find_by(message_id: ref_id)
          if parent&.thread_id.present?
            self.thread_id = parent.thread_id
            return
          end
        end
        self.thread_id = ref_ids.first
        return
      end

      # No references — use in_reply_to as thread anchor
      if in_reply_to.present?
        self.thread_id = in_reply_to
        return
      end

      # No threading headers — use own message_id so replies referencing it will match
      self.thread_id = message_id.presence || Digest::MD5.hexdigest("#{mail_account_id}:#{normalized_subject.downcase}")
    end
  end
end
