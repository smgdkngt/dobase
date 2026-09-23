# frozen_string_literal: true

# Visitors to the demo can't upload anything (Demo.uploads_allowed?). The upload
# forms say so (restrict_in_demo); this catches every other way a file comes in,
# like an image pasted into a doc, which makes a blob through a direct upload.
ActiveSupport.on_load(:active_storage_blob) do
  validate on: :create do
    errors.add(:base, "Uploads are switched off in the demo") unless Demo.uploads_allowed?
  end
end

Rails.application.config.to_prepare do
  # Thumbnails and previews are made from files already here, so they may be stored
  ActiveStorage::VariantWithRecord.prepend Demo::DerivedImages
  ActiveStorage::Preview.prepend Demo::DerivedImages

  ActiveStorage::DirectUploadsController.before_action do
    render json: { error: "Uploads are switched off in the demo" }, status: :forbidden unless Demo.uploads_allowed?
  end
end
