# frozen_string_literal: true

# A card or a todo made of something dropped on its column or list (Dropped): its
# title, a link back to it with a few of its words, and its files
module MadeFromDropped
  extend ActiveSupport::Concern

  def take(dropped, base_url:)
    self.title = dropped.title
    self.description = dropped.html(base_url)
    dropped.blobs.each do |blob|
      attachments.build(filename: blob.filename.to_s, content_type: blob.content_type, file_size: blob.byte_size).file.attach(blob)
    end
    self
  end
end
