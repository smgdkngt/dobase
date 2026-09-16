# frozen_string_literal: true

# Sends an uploaded file under its name a chunk at a time, so a large file doesn't
# have to fit in memory first (uploads go up to 200 MB).
module FileItemDownload
  extend ActiveSupport::Concern

  include ActionController::Live

  private

  def send_file_item(item)
    send_stream(filename: item.name, type: item.content_type.presence || "application/octet-stream", disposition: "attachment") do |stream|
      item.file.download { |chunk| stream.write(chunk) }
    end
  end
end
