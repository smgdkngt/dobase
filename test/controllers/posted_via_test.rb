# frozen_string_literal: true

require "test_helper"

# What an access token posts keeps its owner as the author, and shows either as
# them ("via Claude") or, for an agent token, under the token's own name.
class PostedViaTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)

    chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.assign_attributes(name: "Chat", icon: "messages-square") }
    @tool = Tool.create!(name: "Team Chat", owner: @user, tool_type: chat_type)
    @tool.collaborators.create!(user: @other_user, role: "collaborator")
    @chat = @tool.chat
  end

  test "a token posting as its owner puts their name on the message, via the token" do
    post tool_chat_messages_path(@tool), params: { message: { body: "Deployed" } },
      headers: api_headers(@user, name: "Claude"), as: :json

    assert_response :created
    assert_equal @user.id, response.parsed_body.dig("user", "id")
    assert_equal "Claude", response.parsed_body["via"]
    assert_equal false, response.parsed_body["agent"]

    message = @chat.messages.last
    assert message.written_by?(@user)
    assert_equal 0, @chat.unread_count_for(@user)

    sign_in_as @other_user
    get tool_chat_path(@tool)
    assert_select "##{ActionView::RecordIdentifier.dom_id(message)}" do
      assert_select "span", text: @user.name
      assert_select "span", text: "via Claude"
    end
  end

  test "an agent token posts under its own name, for its owner, and tells them" do
    assert_difference -> { @user.notifications.count }, 1 do
      post tool_chat_messages_path(@tool), params: { message: { body: "Deployed" } },
        headers: api_headers(@user, name: "Claude", agent: true), as: :json
    end

    assert_response :created
    assert_equal @user.id, response.parsed_body.dig("user", "id")
    assert_equal "Claude", response.parsed_body["via"]
    assert response.parsed_body["agent"]

    message = @chat.messages.last
    assert_not message.written_by?(@user)
    assert_equal 1, @chat.unread_count_for(@user)
    assert_includes Tool.unread_tool_ids_for(@user), @tool.id
    assert_equal "Claude for User sent a message in Team Chat", @user.notifications.last.message

    sign_in_as @user
    get tool_chat_path(@tool)
    assert_select "##{ActionView::RecordIdentifier.dom_id(message)}" do
      assert_select "span", text: "Claude"
      assert_select "span", text: "for User"
      assert_select "[aria-label=Agent]"
    end

    get notifications_path
    assert_includes response.body, "Claude for User sent a message in Team Chat"
  end

  test "an agent's message doesn't fold into its owner's group, and replies name the agent" do
    mine = @chat.messages.create!(user: @user, body: "<p>Can you deploy?</p>", created_at: 1.minute.ago)
    post tool_chat_messages_path(@tool), params: { message: { body: "Deployed", reply_to_id: mine.id } },
      headers: api_headers(@user, name: "Claude", agent: true), as: :json
    agents = @chat.messages.last

    assert_not helpers_for_test.chat_continuation?(mine, agents)

    post tool_chat_messages_path(@tool), params: { message: { body: "Thanks", reply_to_id: agents.id } },
      headers: api_headers(@other_user), as: :json
    assert_equal "Claude", response.parsed_body.dig("reply_to", "user_name")
  end

  test "an agent mentioning its owner notifies them" do
    body = %(<p>Done, <span data-id="#{@user.id}" class="mention">@#{@user.name}</span></p>)

    post tool_chat_messages_path(@tool), params: { message: { body: body } },
      headers: api_headers(@user, name: "Claude", agent: true), as: :json

    assert_equal [ "Claude for User mentioned you in a chat message" ], @user.notifications.map(&:message)
  end

  test "renaming or revoking the token keeps the label" do
    headers = api_headers(@user, name: "Claude", agent: true)
    post tool_chat_messages_path(@tool), params: { message: { body: "Deployed" } }, headers: headers, as: :json

    @user.access_tokens.destroy_all

    assert_equal "Claude", @chat.messages.last.via
  end

  test "board comments from an agent show its name" do
    tool = tools(:project_board)
    card = cards(:first_task)

    post tool_board_card_comments_path(tool, card), params: { body: "On it" },
      headers: api_headers(@user, name: "Claude", agent: true), as: :json

    assert_response :created
    assert response.parsed_body["agent"]

    sign_in_as @user
    get tool_board_card_path(tool, card)
    assert_select "##{ActionView::RecordIdentifier.dom_id(card.comments.last)}" do
      assert_select "span", text: "Claude"
      assert_select "span", text: "for User"
    end
  end

  test "todo comments from a token show who it came via" do
    tool = tools(:my_todos)
    item = todo_items(:pending_one)

    post tool_todo_item_comments_path(tool, item), params: { body: "Done" },
      headers: api_headers(@user, name: "Claude"), as: :json

    assert_response :created
    assert_equal "Claude", response.parsed_body["via"]
    assert_equal false, response.parsed_body["agent"]

    sign_in_as @user
    get tool_todo_item_path(tool, item)
    assert_select "##{ActionView::RecordIdentifier.dom_id(item.comments.last)}" do
      assert_select "span", text: "via Claude"
    end
  end

  test "posting in the browser has no label" do
    sign_in_as @user
    post tool_chat_messages_path(@tool), params: { message: { body: "Hi" } }, as: :turbo_stream

    message = @chat.messages.last
    assert_nil message.via
    assert_not message.agent?
  end

  private

  def helpers_for_test
    Object.new.extend(ChatsHelper)
  end
end
