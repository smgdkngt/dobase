# frozen_string_literal: true

# What the app can show of a file without downloading it: a file in the Files tool, an
# attachment of a mail, a card or a todo, a file in a chat. One place says what kind of
# file it is and reads what a page shows of it; `components/media_preview` draws it.
#
# A file is whatever someone sent, so nothing in it is trusted: what is read comes out as
# plain text (never markup), only so much of it is read, and a file that is not what its
# name says simply has nothing to show.
class FilePreview
  # Files worth showing as text, and how much of one to read into a page
  TEXT_CONTENT_TYPES = %w[application/json application/xml application/x-yaml application/yaml application/toml].freeze
  TEXT_EXTENSIONS = %w[
    txt md markdown csv tsv log conf ini env
    json yml yaml toml xml
    rb erb rake py rs go java kt swift c h cpp hpp cs php pl lua ex exs
    mjs cjs ts jsx tsx vue svelte sql css scss sass less graphql
  ].freeze
  MARKDOWN_EXTENSIONS = %w[md markdown].freeze
  MAX_TEXT_BYTES = 512.kilobytes

  # A spreadsheet or a document is read up to this size, and unpacked (an .xlsx and a
  # .docx are zip files, and a small zip can hold gigabytes) up to that one
  MAX_BYTES = 20.megabytes
  MAX_UNPACKED_BYTES = 100.megabytes
  # How much of a table a page shows
  MAX_ROWS = 1000
  MAX_COLUMNS = 50
  MAX_CELL_LENGTH = 500

  SEPARATED_EXTENSIONS = %w[csv tsv].freeze
  SEPARATED_CONTENT_TYPES = %w[text/csv text/tab-separated-values].freeze
  WORKBOOK_EXTENSIONS = %w[xlsx].freeze
  WORKBOOK_CONTENT_TYPES = %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet].freeze
  DOCUMENT_EXTENSIONS = %w[docx].freeze
  DOCUMENT_CONTENT_TYPES = %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document].freeze

  attr_reader :blob, :name

  # `name` when the file goes by another name than it was uploaded with (a renamed file)
  def initialize(blob, name: nil)
    @blob = blob
    @name = (name || blob.filename).to_s
  end

  delegate :content_type, :byte_size, to: :blob

  # What `components/media_preview` asks a file for
  alias_method :file, :blob

  def human_file_size
    HumanFileSize.format(byte_size)
  end

  def extension
    File.extname(name).delete(".").downcase
  end

  # In one word, for the API
  def kind
    if image? then "image"
    elsif video? then "video"
    elsif audio? then "audio"
    elsif pdf? then "pdf"
    elsif table? && sheets then "table"
    elsif document? && document_blocks then "document"
    elsif text? && preview_text then "text"
    end
  end

  # Not an SVG: it is a page with scripts as much as a picture, and is served as a download
  def image?
    content_type.to_s.start_with?("image/") && !content_type.include?("svg")
  end

  # A smaller copy to show on screen, where vips can make one
  def display_copy
    blob.variable? ? blob.variant(resize_to_limit: [ 1600, 1600 ]) : blob
  end

  def video?
    content_type.to_s.start_with?("video/")
  end

  def audio?
    content_type.to_s.start_with?("audio/")
  end

  def pdf?
    content_type == "application/pdf"
  end

  def text?
    content_type.to_s.start_with?("text/") || content_type.in?(TEXT_CONTENT_TYPES) ||
      # By name only when the content isn't media: a .ts is TypeScript, or a video
      (extension.in?(TEXT_EXTENSIONS) && !content_type.to_s.start_with?("video/", "audio/", "image/"))
  end

  def markdown?
    extension.in?(MARKDOWN_EXTENSIONS) || content_type == "text/markdown"
  end

  def preview_too_large?
    byte_size.to_i > MAX_TEXT_BYTES
  end

  # The file's text, as far as a page should show it. Nil when it turns out not to be text
  # after all: the name and the type both only claim it is.
  def preview_text
    return if preview_too_large?

    text = blob.download.force_encoding(Encoding::UTF_8)
    return unless text.valid_encoding?

    text
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  # Rows and columns: a csv or a spreadsheet
  def table?
    separated? || workbook?
  end

  # The file's sheets (FilePreview::Sheet), or nil when it can't be read as a table
  def sheets
    return @sheets if defined?(@sheets)

    @sheets = if byte_size.to_i > MAX_BYTES then nil
    elsif workbook? then blob.open { |file| Workbook.read(file.path) }
    elsif separated? then Separated.read(blob.download, tabs: extension == "tsv" || content_type == "text/tab-separated-values")
    end
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    @sheets = nil
  end

  # A text document from a word processor
  def document?
    extension.in?(DOCUMENT_EXTENSIONS) || content_type.in?(DOCUMENT_CONTENT_TYPES)
  end

  # The document's text in order (FilePreview::WordDocument::Block), or nil when it can't be read
  def document_blocks
    return @document_blocks if defined?(@document_blocks)

    @document_blocks = (blob.open { |file| WordDocument.read(file.path) } unless byte_size.to_i > MAX_BYTES)
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    @document_blocks = nil
  end

  # Something that is read rather than looked at: it gets the whole pane and scrolls in it
  def read?
    text? || pdf? || table? || document?
  end

  # Whether a zip file unpacks to no more than a page should be made to read. What an
  # entry says of its own size is held to when it is read (rubyzip stops at it).
  def self.unpacks_small?(zip)
    zip.sum(&:size) <= MAX_UNPACKED_BYTES
  end

  private

  def separated?
    extension.in?(SEPARATED_EXTENSIONS) || content_type.in?(SEPARATED_CONTENT_TYPES)
  end

  def workbook?
    extension.in?(WORKBOOK_EXTENSIONS) || content_type.in?(WORKBOOK_CONTENT_TYPES)
  end
end
