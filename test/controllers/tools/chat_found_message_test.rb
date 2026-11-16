# frozen_string_literal: true

require "test_helper"

module Tools
  # GET /tools/:tool_id/chat?message=ID: what a mention, a search hit and "Copy link"
  # lead to. The page opens on that message, however far back it is.
  class ChatFoundMessageTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @other_user = users(:two)
      chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "messages-square" }
      @tool = Tool.create!(name: "Team Chat", owner: @user, tool_type: chat_type)
      @tool.collaborators.create!(user: @other_user, role: "collaborator")
      @chat = @tool.chat
      # (written in one go: three hundred messages that each tell everyone take a while)
      ::Chats::Message.insert_all(300.times.map { |i| { chat_id: @chat.id, user_id: @other_user.id, created_at: (300 - i).minutes.ago, updated_at: Time.current } })
      @messages = @chat.messages.order(:created_at, :id).to_a
      sign_in_as @user
    end

    test "a message far back is on the page, with the ones around it and a way back to the newest" do
      found = @messages[60]

      get tool_chat_path(@tool, message: found.id)

      assert_response :success
      assert_select "[data-chat-found-value='#{found.id}']"
      assert_select "[data-message-id='#{found.id}']"
      assert_select "[data-message-id='#{@messages[35].id}']"
      assert_select "[data-message-id='#{@messages[34].id}']", count: 0
      assert_select "[data-message-id='#{@messages.last.id}']", count: 0
      assert_select ".chat-jump-newest a[href='#{tool_chat_path(@tool)}']", text: "Jump to newest"
      # Older ones are read back from the first one showing, as always
      assert_select "a.chat-load-older[href='#{tool_chat_messages_path(@tool, before: @messages[35].id)}']"
    end

    test "a message near the newest shows everything after it, and no jump" do
      found = @messages[280]

      get tool_chat_path(@tool, message: found.id)

      assert_select "[data-message-id='#{@messages.last.id}']"
      assert_select ".chat-jump-newest", count: 0
    end

    test "a message that is gone, or another chat's, opens the chat as it is" do
      other = Tool.create!(name: "Other Chat", owner: @user, tool_type: @tool.tool_type)
      elsewhere = other.chat.messages.create!(user: @user, body: "<p>Elsewhere</p>")

      [ elsewhere.id, 0, "nonsense" ].each do |id|
        get tool_chat_path(@tool, message: id)

        assert_response :success
        assert_select "[data-chat-found-value]", count: 0
        assert_select "[data-message-id='#{@messages.last.id}']"
        assert_select "[data-message-id='#{elsewhere.id}']", count: 0
      end
    end

    test "the API gives the messages around one, and says whether there are newer" do
      found = @messages[60]

      get tool_chat_path(@tool, message: found.id), headers: api_headers(@user)

      body = response.parsed_body
      ids = body["messages"].map { it["id"] }
      assert_equal @messages[35].id, ids.first
      assert_includes ids, found.id
      assert_equal 226, ids.size
      assert body["has_more"]
      assert body["has_newer"]

      get tool_chat_path(@tool), headers: api_headers(@user)
      assert_equal false, response.parsed_body["has_newer"]
    end

    test "a chat message's menu copies a link to it" do
      get tool_chat_path(@tool)

      assert_select "[data-message-id='#{@messages.last.id}'] template" do |template|
        assert_includes template.to_s, %(data-copy-link="#{tool_chat_path(@tool, message: @messages.last.id)}")
      end
    end
  end
end
