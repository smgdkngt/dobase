# frozen_string_literal: true

module Chats
  class Message < ApplicationRecord
    self.table_name = "chat_messages"

    MAX_FILE_SIZE = 50.megabytes
    MAX_FILES = 10

    belongs_to :chat, class_name: "Chats::Chat"
    belongs_to :user
    belongs_to :reply_to, class_name: "Chats::Message", optional: true

    has_many :replies, class_name: "Chats::Message", foreign_key: :reply_to_id, dependent: :nullify
    has_many :read_receipts_as_last_read, class_name: "Chats::ReadReceipt", foreign_key: :last_read_message_id, dependent: :nullify

    has_rich_text :body
    has_many_attached :files

    ALLOWED_CONTENT_TYPES = %w[
      image/jpeg image/png image/gif image/webp
      application/pdf
      application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.ms-powerpoint application/vnd.openxmlformats-officedocument.presentationml.presentation
      text/plain text/csv text/markdown
      application/zip application/x-zip-compressed
      video/mp4 video/webm video/quicktime
      audio/mpeg audio/wav audio/ogg
    ].freeze

    before_validation :strip_trailing_empty_paragraphs

    validates :body, presence: true, unless: :has_files?
    validate :validate_file_count
    validate :validate_file_sizes
    validate :validate_file_content_types
    validate :validate_reply_to_belongs_to_same_chat

    scope :recent, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }
    scope :with_associations, -> { includes(:user, :rich_text_body, :files_attachments, reply_to: [ :user, :rich_text_body ]) }

    def has_files?
      files.attached?
    end

    def image_files
      files.select { |f| f.content_type.start_with?("image/") && !f.content_type.include?("svg") }
    end

    def other_files
      files.reject { |f| f.content_type.start_with?("image/") && !f.content_type.include?("svg") }
    end

    private

    def strip_trailing_empty_paragraphs
      return unless body&.body.present?

      html = body.body.to_html
      cleaned = html.gsub(%r{(<p><br></p>\s*)+\z}, "")
      body.body = cleaned if cleaned != html
    end

    def notify_collaborators
      tool = chat.tool
      recipients = tool.users.where.not(id: user_id)
      return if recipients.none?

      ChatMessageNotifier.with(message: self, sender: user, tool: tool).deliver(recipients)
      recipients.each(&:prune_notifications!)
    end

    def validate_file_count
      return unless files.attached?

      if files.count > MAX_FILES
        errors.add(:files, "cannot exceed #{MAX_FILES} files per message")
      end
    end

    def validate_file_sizes
      return unless files.attached?

      files.each do |file|
        if file.blob.byte_size > MAX_FILE_SIZE
          errors.add(:files, "must be smaller than #{MAX_FILE_SIZE / 1.megabyte}MB each")
          break
        end
      end
    end

    def validate_file_content_types
      return unless files.attached?

      files.each do |file|
        unless ALLOWED_CONTENT_TYPES.include?(file.blob.content_type)
          errors.add(:files, "contains unsupported file type: #{file.blob.content_type}")
          break
        end
      end
    end

    def validate_reply_to_belongs_to_same_chat
      return if reply_to_id.blank?

      unless reply_to&.chat_id == chat_id
        errors.add(:reply_to, "must be a message in the same chat")
      end
    end

    after_create_commit :notify_collaborators
    after_create_commit -> {
      broadcast_append_to chat,
        target: "chat_messages",
        partial: "tools/chats/message",
        locals: { message: self }
    }
    after_update_commit -> {
      broadcast_replace_to chat,
        partial: "tools/chats/message",
        locals: { message: self }
    }
    after_destroy_commit -> { broadcast_remove_to chat }
  end
end
