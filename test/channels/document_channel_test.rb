# frozen_string_literal: true

require "test_helper"

class DocumentChannelTest < ActionCable::Channel::TestCase
  setup do
    @document = docs_documents(:meeting_notes)
  end

  test "someone on the tool listens to the document they are reading" do
    stub_connection current_user: users(:one)

    subscribe document_id: @document.id

    assert subscription.confirmed?
    assert_has_stream_for @document
  end

  test "someone who can't reach the tool is turned away" do
    stub_connection current_user: User.create!(first_name: "Out", last_name: "Sider",
      email_address: "outsider-doc@example.com", password: "password123")

    subscribe document_id: @document.id

    assert subscription.rejected?
  end

  test "a saved document goes out to everyone reading it" do
    assert_broadcasts DocumentChannel.broadcasting_for(@document), 1 do
      @document.broadcast_content_update
    end
  end
end
