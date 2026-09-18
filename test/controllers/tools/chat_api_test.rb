# frozen_string_literal: true

require "test_helper"

module Tools
  class ChatApiTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @other_user = users(:two)
      @headers = api_headers(@user)
      @tool = create_chat_tool("Team Chat")
      @tool.collaborators.create!(user: @other_user, role: "collaborator")
      @chat = @tool.chat
    end

    test "the chat page runs the same number of queries however many messages it holds" do
      sign_in_as @user
      add_messages = -> do
        5.times { |index| @chat.messages.create!(user: @other_user, body: "<p>Message #{index}</p>") }
      end

      assert_queries_independent_of(add_messages) { get tool_chat_path(@tool) }
    end

    test "chat lists messages oldest first with their author, reply and files" do
      first = @chat.messages.create!(user: @other_user, body: "<p>Hello <strong>team</strong>, this is the first message</p>", created_at: 2.minutes.ago)
      reply = @chat.messages.create!(user: @user, body: "<p>Hi!</p>", reply_to: first, created_at: 1.minute.ago)
      reply.files.attach(io: StringIO.new("hello"), filename: "notes.txt", content_type: "text/plain")

      get tool_chat_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal tool_chat_url(@tool), body["url"]
      assert_equal false, body["has_more"]
      assert_equal [ first.id, reply.id ], body["messages"].map { |message| message["id"] }

      message = body["messages"].first
      assert_equal "Hello team, this is the first message", message["body"]
      assert_includes message["body_html"], "<strong>team</strong>"
      assert_equal @other_user.email_address, message.dig("user", "email_address")
      assert_nil message["reply_to"]
      assert_nil message["edited_at"]
      assert_equal [], message["files"]

      message = body["messages"].last
      assert_equal({ "id" => first.id, "user_name" => "User Two", "preview" => "Hello team, this is the first message" }, message["reply_to"])
      assert_equal "notes.txt", message.dig("files", 0, "filename")
      assert_equal "text/plain", message.dig("files", 0, "content_type")
      assert_equal 5, message.dig("files", 0, "byte_size")
      assert message.dig("files", 0, "download_url").start_with?("http://www.example.com/rails/active_storage/")
    end

    test "chat pages back through older messages" do
      messages = 5.times.map { |index| @chat.messages.create!(user: @user, body: "<p>Message #{index + 1}</p>", created_at: (5 - index).minutes.ago) }

      get tool_chat_path(@tool, limit: 2), headers: @headers
      assert_equal [ "Message 4", "Message 5" ], response.parsed_body["messages"].map { |message| message["body"] }
      assert response.parsed_body["has_more"]

      get tool_chat_path(@tool, limit: 2, before: messages[3].id), headers: @headers
      assert_equal [ "Message 2", "Message 3" ], response.parsed_body["messages"].map { |message| message["body"] }
      assert response.parsed_body["has_more"]

      get tool_chat_path(@tool, limit: 2, before: messages[1].id), headers: @headers
      assert_equal [ "Message 1" ], response.parsed_body["messages"].map { |message| message["body"] }
      assert_not response.parsed_body["has_more"]
    end

    test "chat pages through messages sent at the same moment" do
      sent_at = 1.minute.ago
      messages = 3.times.map { |index| @chat.messages.create!(user: @user, body: "<p>Same time #{index + 1}</p>", created_at: sent_at) }

      get tool_chat_path(@tool, limit: 1, before: messages.last.id), headers: @headers

      assert_equal [ "Same time 2" ], response.parsed_body["messages"].map { |message| message["body"] }
      assert response.parsed_body["has_more"]
    end

    test "chat returns 50 messages by default and at most 200" do
      ::Chats::Message.insert_all(205.times.map { |index|
        { chat_id: @chat.id, user_id: @user.id, created_at: (205 - index).seconds.ago, updated_at: Time.current }
      })

      get tool_chat_path(@tool), headers: @headers
      assert_equal 50, response.parsed_body["messages"].size

      get tool_chat_path(@tool, limit: 1000), headers: @headers
      assert_equal 200, response.parsed_body["messages"].size
      assert response.parsed_body["has_more"]
    end

    test "chat refuses a before message from another chat" do
      other_message = create_chat_tool("Elsewhere").chat.messages.create!(user: @user, body: "<p>Other</p>")

      get tool_chat_path(@tool, before: other_message.id), headers: @headers

      assert_response :not_found
    end

    test "chat answers 404 for a before that isn't a message id" do
      get tool_chat_path(@tool, before: [ "1" ]), headers: @headers

      assert_response :not_found
    end

    test "reading the chat through the API doesn't mark it read" do
      @chat.messages.create!(user: @other_user, body: "<p>Unread</p>")

      assert_no_difference -> { ::Chats::ReadReceipt.count } do
        get tool_chat_path(@tool), headers: @headers
      end

      assert_response :success
      assert_equal 1, @chat.unread_count_for(@user)
    end

    test "the chat page in the browser still marks it read" do
      @chat.messages.create!(user: @other_user, body: "<p>Unread</p>")
      sign_in_as @user

      get tool_chat_path(@tool)

      assert_response :success
      assert_equal 0, @chat.unread_count_for(@user)
    end

    test "chat is forbidden for tools the user can't access" do
      get tool_chat_path(@tool), headers: api_headers(users(:with_otp))

      assert_response :forbidden
    end

    test "create posts a message and notifies the other collaborators" do
      assert_difference -> { @other_user.notifications.count }, 1 do
        post tool_chat_messages_path(@tool), params: { message: { body: "<p>Shipping <em>today</em></p>" } }, headers: @headers, as: :json
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "Shipping today", body["body"]
      assert_includes body["body_html"], "<em>today</em>"
      assert_equal @user.id, body.dig("user", "id")
      assert_equal @chat.messages.last.id, body["id"]
    end

    test "create accepts a flat JSON body" do
      post tool_chat_messages_path(@tool), params: { body: "<p>Flat</p>" }, headers: @headers, as: :json

      assert_response :created
      assert_equal "Flat", response.parsed_body["body"]
    end

    test "create replies to a message" do
      original = @chat.messages.create!(user: @other_user, body: "<p>Who's on it?</p>")

      post tool_chat_messages_path(@tool), params: { message: { body: "<p>Me</p>", reply_to_id: original.id } }, headers: @headers, as: :json

      assert_response :created
      assert_equal original.id, response.parsed_body.dig("reply_to", "id")
      assert_equal "Who's on it?", response.parsed_body.dig("reply_to", "preview")
    end

    test "create refuses a reply to a message in another chat" do
      other_message = create_chat_tool("Elsewhere").chat.messages.create!(user: @user, body: "<p>Other</p>")

      assert_no_difference -> { ::Chats::Message.count } do
        post tool_chat_messages_path(@tool), params: { message: { body: "<p>Me</p>", reply_to_id: other_message.id } }, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Reply to must be a message in the same chat"
    end

    test "create without a body or files returns errors" do
      post tool_chat_messages_path(@tool), params: { message: { body: "" } }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Body can't be blank"
    end

    test "create uploads files as multipart form data" do
      file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")

      post tool_chat_messages_path(@tool), params: { message: { files: [ file ] } }, headers: @headers

      assert_response :created
      assert_equal "", response.parsed_body["body"]
      assert_equal [ "notes.txt" ], response.parsed_body["files"].map { |attachment| attachment["filename"] }
    end

    test "the browser form still gets a status and turbo stream errors" do
      sign_in_as @user
      turbo_headers = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

      post tool_chat_messages_path(@tool), params: { message: { body: "<p>From the browser</p>" } }, headers: turbo_headers
      assert_response :ok
      # Clears the error slot (a stream that updates it to nothing) rather
      # than a bare empty body, so a previous failed attempt's error doesn't
      # linger once a send succeeds.
      assert_includes response.body, "chat-form-errors"

      post tool_chat_messages_path(@tool), params: { message: { body: "" } }, headers: turbo_headers
      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "chat-form-errors"

      delete tool_chat_message_path(@tool, @chat.messages.last), headers: turbo_headers
      assert_response :ok
      assert_equal 0, @chat.messages.count
    end

    test "a single message can be fetched on its own" do
      message = @chat.messages.create!(user: @other_user, body: "<p>Just this one</p>")

      get tool_chat_message_path(@tool, message), headers: @headers

      assert_response :success
      assert_equal message.id, response.parsed_body["id"]
      assert_equal "Just this one", response.parsed_body["body"]
      assert_equal @other_user.id, response.parsed_body.dig("user", "id")
    end

    test "update edits your own message" do
      message = @chat.messages.create!(user: @user, body: "<p>Typo</p>")

      patch tool_chat_message_path(@tool, message), params: { message: { body: "<p>Fixed</p>" } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Fixed", response.parsed_body["body"]
      assert_not_nil response.parsed_body["edited_at"]
      assert_equal "Fixed", message.reload.body.to_plain_text
    end

    test "update leaves the body alone when the request doesn't mention it" do
      message = @chat.messages.create!(user: @user, body: "<p>Keep me</p>")
      message.files.attach(io: StringIO.new("hi"), filename: "notes.txt", content_type: "text/plain")
      message.save!

      patch tool_chat_message_path(@tool, message), params: { message: { reply_to_id: nil } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Keep me", message.reload.body.to_plain_text
    end

    test "update without a message answers 400 instead of blanking the body" do
      message = @chat.messages.create!(user: @user, body: "<p>Keep me</p>")
      message.files.attach(io: StringIO.new("hi"), filename: "notes.txt", content_type: "text/plain")
      message.save!

      patch tool_chat_message_path(@tool, message), params: {}, headers: @headers, as: :json

      assert_response :bad_request
      assert_equal "Keep me", message.reload.body.to_plain_text
    end

    test "update refuses someone else's message" do
      message = @chat.messages.create!(user: @other_user, body: "<p>Mine</p>")

      patch tool_chat_message_path(@tool, message), params: { message: { body: "<p>Hijacked</p>" } }, headers: @headers, as: :json

      assert_response :forbidden
      assert_equal "Only the author can edit this message", response.parsed_body["error"]
      assert_equal "Mine", message.reload.body.to_plain_text
    end

    test "destroy removes your own message" do
      message = @chat.messages.create!(user: @other_user, body: "<p>Oops</p>")

      delete tool_chat_message_path(@tool, message), headers: api_headers(@other_user), as: :json

      assert_response :no_content
      assert_not ::Chats::Message.exists?(message.id)
    end

    test "owners can delete anyone's message, collaborators only their own" do
      owner_message = @chat.messages.create!(user: @user, body: "<p>Owner</p>")
      other_message = @chat.messages.create!(user: @other_user, body: "<p>Collaborator</p>")

      delete tool_chat_message_path(@tool, owner_message), headers: api_headers(@other_user), as: :json
      assert_response :forbidden
      assert_equal "Only the author or an owner can delete this message", response.parsed_body["error"]
      assert ::Chats::Message.exists?(owner_message.id)

      delete tool_chat_message_path(@tool, other_message), headers: @headers, as: :json
      assert_response :no_content
      assert_not ::Chats::Message.exists?(other_message.id)
    end

    test "messages from another chat are not found" do
      other_message = create_chat_tool("Elsewhere").chat.messages.create!(user: @user, body: "<p>Other</p>")

      patch tool_chat_message_path(@tool, other_message), params: { message: { body: "<p>Moved</p>" } }, headers: @headers, as: :json
      assert_response :not_found

      delete tool_chat_message_path(@tool, other_message), headers: @headers, as: :json
      assert_response :not_found
      assert ::Chats::Message.exists?(other_message.id)
    end

    test "read marks the chat read up to the latest message" do
      @chat.messages.create!(user: @other_user, body: "<p>First</p>", created_at: 1.minute.ago)
      latest = @chat.messages.create!(user: @other_user, body: "<p>Latest</p>")

      post tool_chat_read_path(@tool), headers: @headers, as: :json

      assert_response :success
      assert_equal latest.id, response.parsed_body["last_read_message_id"]
      assert_not_nil response.parsed_body["last_read_at"]
      assert_equal 0, @chat.unread_count_for(@user)
    end

    test "read-only tokens can read the chat but not post or mark it read" do
      headers = api_headers(@user, permission: "read")

      get tool_chat_path(@tool), headers: headers
      assert_response :success

      assert_no_difference -> { ::Chats::Message.count } do
        post tool_chat_messages_path(@tool), params: { message: { body: "<p>Nope</p>" } }, headers: headers, as: :json
      end
      assert_response :forbidden

      post tool_chat_read_path(@tool), headers: headers, as: :json
      assert_response :forbidden
      assert_not ::Chats::ReadReceipt.exists?(chat: @chat, user: @user)
    end

    private

    def create_chat_tool(name)
      chat_type = ToolType.find_or_create_by!(slug: "chat") do |tool_type|
        tool_type.name = "Chat"
        tool_type.icon = "messages-square"
      end

      Tool.create!(name: name, owner: @user, tool_type: chat_type)
    end
  end
end
