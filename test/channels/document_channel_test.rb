# frozen_string_literal: true

require "test_helper"

class DocumentChannelTest < ActionCable::Channel::TestCase
  setup do
    @document = docs_documents(:meeting_notes)
    stub_connection current_user: users(:one)
    subscribe document_id: @document.id
  end

  test "refreshing takes the lock back after another tab released it" do
    perform :start_editing
    assert_equal users(:one), @document.reload.locked_by

    # The same document in another tab of the same user closed and released the lock
    @document.update_columns(locked_by_id: nil, locked_at: nil)
    perform :refresh_lock

    assert_equal users(:one), @document.reload.locked_by
  end

  test "refreshing doesn't take a lock someone else holds, and says who has it" do
    @document.update_columns(locked_by_id: users(:two).id, locked_at: Time.current)

    perform :refresh_lock

    assert_equal users(:two), @document.reload.locked_by
    assert_equal({ "type" => "lock_rejected", "locked_by" => users(:two).name }, transmissions.last)
  end

  test "closing a tab that only read the document keeps the lock it holds elsewhere" do
    # Another tab of the same user has the editor open and holds the lock
    @document.update_columns(locked_by_id: users(:one).id, locked_at: Time.current)

    unsubscribe

    assert_equal users(:one), @document.reload.locked_by
  end

  test "closing the editing tab releases the lock" do
    perform :start_editing

    unsubscribe

    assert_nil @document.reload.locked_by
  end
end
