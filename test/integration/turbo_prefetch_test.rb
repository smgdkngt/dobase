# frozen_string_literal: true

require "test_helper"

# Turbo prefetches links on hover by default. Visiting a page here changes
# things (mail gets marked read, documents get locked for editing, activity
# dots clear, share downloads are counted), so hovering must not visit.
class TurboPrefetchTest < ActionDispatch::IntegrationTest
  test "app pages don't prefetch links on hover" do
    sign_in_as users(:one)

    get tool_path(tools(:my_files))
    follow_redirect! while response.redirect?

    assert_select "meta[name='turbo-prefetch'][content='false']"
  end

  test "share pages don't prefetch, and their download bypasses Turbo" do
    file = file_items(:report)
    file.file.attach(io: StringIO.new("%PDF-1.4"), filename: "report.pdf", content_type: "application/pdf")
    share = Files::Share.create!(shareable: file, created_by: users(:one))

    get share_path(share.token)

    assert_select "meta[name='turbo-prefetch'][content='false']"
    assert_select "a[href='#{share_download_path(share.token)}'][data-turbo='false']"
  end
end
