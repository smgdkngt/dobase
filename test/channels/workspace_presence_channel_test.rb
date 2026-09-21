# frozen_string_literal: true

require "test_helper"

class WorkspacePresenceChannelTest < ActionCable::Channel::TestCase
  test "the sidebar listens to every tool you share, and no other" do
    stub_connection current_user: users(:two)

    subscribe

    assert subscription.confirmed?
    assert_includes subscription.streams, PresenceChannel.broadcasting_for(tools(:shared_board))
    assert_not_includes subscription.streams, PresenceChannel.broadcasting_for(tools(:my_files))
  end

  test "a roll call asks everyone on each of those tools to say where they are" do
    stub_connection current_user: users(:two)
    subscribe

    assert_broadcast_on(PresenceChannel.broadcasting_for(tools(:shared_board)),
      type: "roll_call", tool_id: tools(:shared_board).id) do
      perform :roll_call
    end
  end
end
