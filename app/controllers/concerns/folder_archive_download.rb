# frozen_string_literal: true

# Sends a Files::FolderArchive. The zip is written to a temp file and streamed
# from there in chunks, so memory use doesn't grow with the size of the folder.
# The temp file is removed when the response is done, or when the client gives up.
module FolderArchiveDownload
  extend ActiveSupport::Concern

  include ActionController::Live

  private

  def send_folder_archive(archive)
    Tempfile.create([ "folder", ".zip" ], binmode: true) do |file|
      archive.write(file.path)

      send_stream(filename: archive.filename, type: "application/zip") do |stream|
        while (chunk = file.read(64.kilobytes))
          stream.write(chunk)
        end
      end
    end
  end
end
