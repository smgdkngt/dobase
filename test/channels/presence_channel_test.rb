# frozen_string_literal: true

require "test_helper"

class PresenceChannelTest < ActionCable::Channel::TestCase
  setup do
    @tool = tools(:shared_board)
    @user = users(:one)
    ToolPresence.reset!
  end

  test "someone on the tool arrives with a hello" do
    stub_connection current_user: @user

    assert_broadcast_on(PresenceChannel.broadcasting_for(@tool), here(hello: true)) do
      subscribe tool_id: @tool.id
    end

    assert subscription.confirmed?
    assert_has_stream_for @tool
  end

  test "someone who can't reach the tool is turned away" do
    stub_connection current_user: User.create!(first_name: "Out", last_name: "Sider", email_address: "outsider@example.com", password: "password123")

    subscribe tool_id: @tool.id

    assert subscription.rejected?
  end

  test "an answer to a hello says where you are, without asking back" do
    stub_connection current_user: @user
    subscribe tool_id: @tool.id

    assert_broadcast_on(PresenceChannel.broadcasting_for(@tool), here(context: "card:12")) do
      perform :answer, context: "card:12"
    end
  end

  test "the page says what it has open, not who has it open" do
    stub_connection current_user: @user
    subscribe tool_id: @tool.id

    assert_broadcast_on(PresenceChannel.broadcasting_for(@tool), here(context: nil)) do
      perform :announce, context: "<script>alert(1)</script>", user: { id: users(:two).id, name: "Someone else" }
    end
  end

  test "the last tab to close is the one that says you left" do
    stub_connection current_user: @user
    subscribe tool_id: @tool.id
    ToolPresence.connect(@tool.id, @user.id) # a second tab

    assert_no_broadcasts(PresenceChannel.broadcasting_for(@tool)) do
      unsubscribe
    end

    subscribe tool_id: @tool.id
    ToolPresence.reset!
    ToolPresence.connect(@tool.id, @user.id)

    assert_broadcast_on(PresenceChannel.broadcasting_for(@tool), type: "gone", tool_id: @tool.id, user: user_payload) do
      unsubscribe
    end
  end

  test "a face carries the picture of whoever has one, without resizing it first" do
    @user.avatar.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.png")),
      filename: "sample.png", content_type: "image/png")
    stub_connection current_user: @user

    subscribe tool_id: @tool.id

    avatar_url = broadcasts(PresenceChannel.broadcasting_for(@tool)).last.then { |message| JSON.parse(message)["user"]["avatar_url"] }
    assert_match %r{\A/rails/active_storage/representations/}, avatar_url
    assert_not @user.avatar.variant(resize_to_fill: [ 200, 200 ]).send(:processed?),
      "the picture should be made when a browser asks for it, not while someone is arriving"
  end

  private

  def here(context: nil, hello: false)
    { type: "here", context: context, hello: hello, tool_id: @tool.id, user: user_payload }
  end

  def user_payload
    { id: @user.id, name: @user.name, initials: @user.initials, avatar_url: nil }
  end
end
