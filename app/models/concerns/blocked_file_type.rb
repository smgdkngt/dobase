# frozen_string_literal: true

# Refuses uploads that run as programs: installers, scripts and the like. Every download
# of them is served as an attachment, but a blocklist keeps them out in the first place.
module BlockedFileType
  extend ActiveSupport::Concern

  EXTENSIONS = %w[
    exe msi bat cmd com scr pif
    sh bash ps1 vbs vbe js jse ws wsf
    dll sys drv
    reg inf hta cpl
    app dmg pkg
  ].freeze

  CONTENT_TYPES = %w[
    application/x-msdownload
    application/x-executable
    application/x-msdos-program
    application/x-sh
    application/x-shellscript
  ].freeze

  included do
    validate :file_type_allowed, if: -> { file.attached? }
  end

  private

  def file_type_allowed
    extension = File.extname(file.filename.to_s).delete(".").downcase
    if EXTENSIONS.include?(extension)
      errors.add(:file, "type .#{extension} is not allowed for security reasons")
    elsif CONTENT_TYPES.any? { |type| file.blob.content_type.to_s.include?(type) }
      errors.add(:file, "type is not allowed for security reasons")
    end
  end
end
