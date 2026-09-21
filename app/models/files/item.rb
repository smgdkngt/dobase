# frozen_string_literal: true

module Files
  class Item < ApplicationRecord
    include HumanFileSize
    include Trackable
    include BlockedFileType

    self.table_name = "file_items"

    MAX_FILE_SIZE = 200.megabytes

    # Files worth showing as text, and how much of one to read into a page
    TEXT_CONTENT_TYPES = %w[application/json application/xml application/x-yaml application/yaml application/toml].freeze
    TEXT_EXTENSIONS = %w[
      txt md markdown csv tsv log conf ini env
      json yml yaml toml xml
      rb erb rake py rs go java kt swift c h cpp hpp cs php pl lua ex exs
      mjs cjs ts jsx tsx vue svelte sql css scss sass less graphql
    ].freeze
    MARKDOWN_EXTENSIONS = %w[md markdown].freeze
    MAX_PREVIEW_BYTES = 512.kilobytes

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

    def text?
      return false unless file.attached?

      content_type.to_s.start_with?("text/") || content_type.in?(TEXT_CONTENT_TYPES) ||
        # By name only when the content isn't media: a .ts is TypeScript, or a video
        (extension.in?(TEXT_EXTENSIONS) && !content_type.to_s.start_with?("video/", "audio/", "image/"))
    end

    def markdown?
      extension.in?(MARKDOWN_EXTENSIONS) || content_type == "text/markdown"
    end

    def preview_too_large?
      file_size.to_i > MAX_PREVIEW_BYTES
    end

    # The file's text, as far as a page should show it. Nil when it turns out not to be text
    # after all: the name and the type both only claim it is.
    def preview_text
      return if preview_too_large?

      text = file.download.force_encoding(Encoding::UTF_8)
      return unless text.valid_encoding?

      text
    rescue ActiveStorage::FileNotFoundError
      nil
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
