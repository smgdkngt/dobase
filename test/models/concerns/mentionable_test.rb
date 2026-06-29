# frozen_string_literal: true

require "test_helper"

class MentionableTest < ActiveSupport::TestCase
  setup do
    @tool = tools(:shared_board)        # user_one owner, user_two collaborator
    @author = users(:one)
    @other = users(:two)
    @chat = Chats::Chat.create!(tool: @tool)
  end

  def message_with(body)
    Chats::Message.new(chat: @chat, user: @author, body: body)
  end

  test "parses mentioned user ids from data-id spans" do
    msg = message_with(%(<p>hey <span data-id="#{@other.id}" class="mention">@User Two</span></p>))
    assert_equal [ @other.id ], msg.mentioned_user_ids
  end

  test "returns no ids when the body has no mentions" do
    assert_empty message_with("<p>just text</p>").mentioned_user_ids
  end

  test "deduplicates repeated mentions of the same user" do
    span = %(<span data-id="#{@other.id}" class="mention">@User Two</span>)
    assert_equal [ @other.id ], message_with("<p>#{span} and #{span}</p>").mentioned_user_ids
  end

  test "mentioned_users_in scopes to tool collaborators" do
    stranger = User.create!(first_name: "Out", last_name: "Sider", email_address: "out@example.com", password: "password123")
    body = %(<span data-id="#{@other.id}">@Two</span><span data-id="#{stranger.id}">@Out</span>)

    users = message_with(body).mentioned_users_in(@tool)

    assert_includes users, @other
    refute_includes users, stranger, "a non-collaborator id must not resolve to a mention"
  end

  test "mentioned_users_in can exclude the author" do
    body = %(<span data-id="#{@author.id}">@me</span><span data-id="#{@other.id}">@Two</span>)

    users = message_with(body).mentioned_users_in(@tool, excluding: @author)

    refute_includes users, @author
    assert_includes users, @other
  end

  test "mentioned_users_in skips collaborators who muted the tool" do
    collaborators(:two_shared_board).mute!
    body = %(<span data-id="#{@other.id}">@Two</span>)

    assert_empty message_with(body).mentioned_users_in(@tool)
  end
end
