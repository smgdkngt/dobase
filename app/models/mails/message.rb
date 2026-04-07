# frozen_string_literal: true

module Mails
  class Message < ApplicationRecord
    self.table_name = "mail_messages"

    belongs_to :account, class_name: "Mails::Account", foreign_key: "mail_account_id"
    has_many :attachments, class_name: "Mails::Attachment", foreign_key: "mail_message_id", dependent: :destroy
    has_many :label_assignments, class_name: "Mails::LabelAssignment", foreign_key: "mail_message_id", dependent: :destroy
    has_many :labels, through: :label_assignments, source: :label
    has_many :calendar_invites, class_name: "Calendars::Invite", foreign_key: "mail_message_id", dependent: :destroy

    validates :message_id, presence: true, uniqueness: { scope: :mail_account_id }

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

    def body
      body_html.presence || body_plain
    end

    def display_from
      from_name.presence || from_address
    end

    def preview
      return "" if body_plain.blank?
      body_plain.gsub(/\s+/, " ").strip.truncate(120)
    end

    def mark_as_read!
      update!(read: true)
      sync_read_flag_to_imap(true)
    end

    def mark_as_unread!
      update!(read: false)
      sync_read_flag_to_imap(false)
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

    private

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
