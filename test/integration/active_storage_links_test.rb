# frozen_string_literal: true

require "test_helper"

class ActiveStorageLinksTest < ActionDispatch::IntegrationTest
  test "links to uploads stop working after a day" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("quarterly numbers"), filename: "report.pdf", content_type: "application/pdf")
    link = rails_blob_path(blob, disposition: "attachment")

    get link
    assert_response :redirect

    travel 25.hours do
      get link
      assert_response :not_found
    end
  end
end
