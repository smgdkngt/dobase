# frozen_string_literal: true

module Files
  class Item < ApplicationRecord
    include HumanFileSize
    include Trackable
    include BlockedFileType

    self.table_name = "file_items"

    MAX_FILE_SIZE = 200.megabytes

    belongs_to :tool
    belongs_to :folder, class_name: "Files::Folder", optional: true
    has_one :share, as: :shareable, class_name: "Files::Share", dependent: :destroy
    # A folder full of photos used to load every original in full. Thumbnails are made when
    # a file is uploaded, and a smaller copy is used to show a picture on screen.
    has_one_attached :file do |attachable|
      attachable.variant :thumb, resize_to_limit: [ 480, 480 ], preprocessed: true
      attachable.variant :preview, resize_to_limit: [ 1600, 1600 ]
    end

    validates :name, presence: true
    validate :file_size_limit, if: -> { file.attached? }
    # Downloads and share links serve the file under its name, not the one it
    # was uploaded with, so a rename is held to the blocked types as well
    validate :name_type_allowed, if: :will_save_change_to_name?

    scope :roots, -> { where(folder_id: nil) }
    scope :ordered, -> { order(:position, :name) }

    before_save :cache_file_metadata, if: -> { file.attached? }

    def extension
      File.extname(name).delete(".").downcase
    end

    def image?
      content_type&.start_with?("image/")
    end

    # SVGs and anything else vips can't read stay as they are
    def thumbnail
      file.variable? ? file.variant(:thumb) : file
    end

    def display_copy
      file.variable? ? file.variant(:preview) : file
    end

    def video?
      content_type&.start_with?("video/")
    end

    def audio?
      content_type&.start_with?("audio/")
    end

    # What a page shows of the file without downloading it: FilePreview reads it, for
    # this file as for an attachment anywhere else
    def preview
      FilePreview.new(file.blob, name: name) if file.attached?
    end

    delegate :text?, :markdown?, :preview_too_large?, :preview_text,
      :table?, :sheets, :document?, :document_blocks, :read?, to: :preview, allow_nil: true

    def pdf?
      content_type == "application/pdf"
    end

    def previewable?
      image? || video? || audio? || pdf?
    end

    def icon_name
      case
      when image? then "image"
      when video? then "video"
      when audio? then "music"
      when pdf? then "file-text"
      when content_type&.include?("spreadsheet") || %w[xls xlsx csv].include?(extension)
        "table"
      # Before documents: PowerPoint's type, ...officedocument.presentationml.presentation, says "document" too
      when content_type&.include?("presentation") || content_type&.include?("powerpoint") || %w[ppt pptx key odp].include?(extension)
        "presentation"
      when content_type&.include?("document") || content_type == "application/msword" || %w[doc docx].include?(extension)
        "file-text"
      when %w[zip rar 7z tar gz].include?(extension)
        "archive"
      else
        "file"
      end
    end

    private

    def cache_file_metadata
      self.file_size = file.blob.byte_size
      self.content_type = file.blob.content_type
    end

    # The same words as for a refused upload, and said once when both the
    # upload and the name it gets are a program
    def name_type_allowed
      return unless (extension = BlockedFileType.blocked_extension(name))

      message = "type .#{extension} is not allowed for security reasons"
      errors.add(:file, message) unless errors.added?(:file, message)
    end

    def file_size_limit
      if file.blob.byte_size > MAX_FILE_SIZE
        errors.add(:file, "is too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB")
      end
    end
  end
end
