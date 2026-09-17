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
    has_one_attached :file

    validates :name, presence: true
    validate :file_size_limit, if: -> { file.attached? }

    scope :roots, -> { where(folder_id: nil) }
    scope :ordered, -> { order(:position, :name) }

    before_save :cache_file_metadata, if: -> { file.attached? }

    def extension
      File.extname(name).delete(".").downcase
    end

    def image?
      content_type&.start_with?("image/")
    end

    def video?
      content_type&.start_with?("video/")
    end

    def audio?
      content_type&.start_with?("audio/")
    end

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

    def file_size_limit
      if file.blob.byte_size > MAX_FILE_SIZE
        errors.add(:file, "is too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB")
      end
    end
  end
end
