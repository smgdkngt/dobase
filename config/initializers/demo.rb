# frozen_string_literal: true

# Files, chat and attachments check the demo's upload limit themselves. Direct uploads,
# like an image pasted into a doc, only make a blob, so the demo checks blobs too.
ActiveSupport.on_load(:active_storage_blob) do
  validate on: :create, if: -> { Demo.enabled? } do
    if byte_size.to_i > Demo::MAX_UPLOAD_SIZE
      errors.add(:byte_size, "is too large for the demo (max #{Demo::MAX_UPLOAD_SIZE / 1.megabyte} MB)")
    end
  end
end
