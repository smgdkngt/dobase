# frozen_string_literal: true

require "test_helper"

class DocsChannelTest < ActionCable::Channel::TestCase
  test "collaborators follow a docs tool" do
    stub_connection current_user: users(:one)

    subscribe tool_id: tools(:my_docs).id

    assert subscription.confirmed?
    assert_has_stream_for tools(:my_docs)
  end

  test "others and unknown tools are rejected" do
    stub_connection current_user: users(:two)
    subscribe tool_id: tools(:my_docs).id
    assert subscription.rejected?

    subscribe tool_id: 0
    assert subscription.rejected?
  end
end
