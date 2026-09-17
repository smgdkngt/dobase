# frozen_string_literal: true

require "test_helper"

module Tools
  class TodosApiTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @headers = api_headers(@user)
      @tool = tools(:my_todos)
      @list = todo_lists(:main)
      @item = todo_items(:pending_one)
    end

    test "todo lists the lists in order with open and recently completed items" do
      get tool_todo_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal tool_todo_url(@tool), body["url"]
      assert_equal [ "To Do", "Backlog" ], body["lists"].map { |list| list["title"] }

      items = body["lists"].first["items"]
      assert_equal [ "Buy groceries", "Call dentist", "Send report" ], items.map { |item| item["title"] }
      assert_equal [ false, false, true ], items.map { |item| item["completed"] }
      assert_equal tool_todo_url(@tool, item: @item.id), items.first["url"]
      assert_equal @list.id, items.first["todo_list_id"]
      assert_equal 1, items.first["comments_count"]
      assert_nil items.first["assignee"]
      assert_equal [], body["lists"].second["items"]
    end

    test "todo lists open items before completed ones" do
      @item.update!(completed_at: 1.hour.ago)

      get tool_todo_path(@tool), headers: @headers

      titles = response.parsed_body["lists"].first["items"].map { |item| item["title"] }
      assert_equal [ "Call dentist", "Buy groceries", "Send report" ], titles
    end

    test "todo with completed=true lists every completed item" do
      get tool_todo_path(@tool, completed: true), headers: @headers

      items = response.parsed_body["lists"].flat_map { |list| list["items"] }
      assert_equal [ "Send report", "Fix bug" ], items.map { |item| item["title"] }
      assert items.all? { |item| item["completed"] && item["completed_at"] }
    end

    test "todo is forbidden for tools the user can't access" do
      get tool_todo_path(@tool), headers: api_headers(users(:two))

      assert_response :forbidden
    end

    test "item shows description, list, creator, comments and attachments" do
      @item.update!(description: "<p>Milk, <strong>eggs</strong></p>", created_by: @user)
      @item.comments.create!(user: @user, body: "<p>Got <em>milk</em></p>")
      attachment = @item.attachments.create!(filename: "list.txt", content_type: "text/plain", file_size: 5)
      attachment.file.attach(io: StringIO.new("hello"), filename: "list.txt")

      get tool_todo_item_path(@tool, @item), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal "Buy groceries", body["title"]
      assert_equal "Milk, eggs", body["description"]
      assert_includes body["description_html"], "<strong>eggs</strong>"
      assert_equal({ "id" => @list.id, "title" => "To Do", "position" => 0 }, body["list"])
      assert_equal @user.email_address, body.dig("creator", "email_address")
      assert_equal "Got milk", body["comments"].last["body"]
      assert_includes body["comments"].last["body_html"], "<em>milk</em>"
      assert_equal @user.id, body["comments"].last.dig("user", "id")
      assert_equal [ "list.txt" ], body["attachments"].map { |file| file["filename"] }
      assert body["attachments"].first["download_url"].present?
    end

    test "create adds an item with all attributes and notifies the assignee" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        post todo_list_items_path(@list), headers: @headers, as: :json, params: {
          item: { title: "Ship API", description: "<p>With a CLI</p>", due_date: "2026-10-01", assigned_user_id: user_two.id, recurrence_rule: "weekly" }
        }
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "Ship API", body["title"]
      assert_equal "With a CLI", body["description"]
      assert_equal "2026-10-01", body["due_date"]
      assert_equal "weekly", body["recurrence_rule"]
      assert_equal user_two.id, body.dig("assignee", "id")
      assert_equal @user.id, body.dig("creator", "id")
      assert_equal "To Do", body.dig("list", "title")
      assert_not body["completed"]
      assert_equal @list.items.maximum(:position), body["position"]
      assert_kind_of TodoAssignmentNotifier, user_two.notifications.last.event
    end

    test "create doesn't notify people who assign themselves" do
      assert_no_difference -> { Noticed::Notification.count } do
        post todo_list_items_path(@list), params: { item: { title: "Mine", assigned_user_id: @user.id } }, headers: @headers, as: :json
      end

      assert_response :created
      assert_equal @user.id, response.parsed_body.dig("assignee", "id")
    end

    test "create without a title returns errors" do
      post todo_list_items_path(@list), params: { item: { title: "" } }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
    end

    test "create is forbidden in lists of tools the user can't access" do
      assert_no_difference -> { ::Todos::Item.count } do
        post todo_list_items_path(@list), params: { item: { title: "Sneaky" } }, headers: api_headers(users(:two)), as: :json
      end

      assert_response :forbidden
    end

    test "update returns the item" do
      @item.update!(due_date: Date.current, recurrence_rule: "daily")

      patch tool_todo_item_path(@tool, @item), params: { item: { title: "Renamed", due_date: nil, recurrence_rule: nil } }, headers: @headers, as: :json

      assert_response :success
      body = response.parsed_body
      assert_equal "Renamed", body["title"]
      assert_nil body["due_date"]
      assert_nil body["recurrence_rule"]
    end

    test "update with an unknown recurrence rule returns errors" do
      patch tool_todo_item_path(@tool, @item), params: { item: { recurrence_rule: "hourly" } }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Recurrence rule is not included in the list"
    end

    test "update notifies a new assignee only when the assignee changes" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        patch tool_todo_item_path(@tool, @item), params: { item: { assigned_user_id: user_two.id } }, headers: @headers, as: :json
        patch tool_todo_item_path(@tool, @item), params: { item: { title: "Still theirs" } }, headers: @headers, as: :json
      end

      assert_equal user_two.id, response.parsed_body.dig("assignee", "id")
    end

    test "update doesn't notify assignees who muted the tool" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator", muted_at: Time.current)

      assert_no_difference -> { Noticed::Notification.count } do
        patch tool_todo_item_path(@tool, @item), params: { item: { assigned_user_id: user_two.id } }, headers: @headers, as: :json
      end

      assert_response :success
      assert_equal user_two.id, response.parsed_body.dig("assignee", "id")
    end

    test "destroy returns no content" do
      delete tool_todo_item_path(@tool, @item), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Todos::Item.exists?(@item.id)
    end

    test "completing and reopening return the item" do
      post tool_todo_item_completion_path(@tool, @item), headers: @headers, as: :json
      assert_response :success
      assert response.parsed_body["completed"]
      assert_not_nil response.parsed_body["completed_at"]

      delete tool_todo_item_completion_path(@tool, @item), headers: @headers, as: :json
      assert_response :success
      assert_not response.parsed_body["completed"]
      assert_nil response.parsed_body["completed_at"]
    end

    test "completing a recurring item adds the next one, even when retried" do
      @item.update!(recurrence_rule: "weekly", due_date: Date.new(2026, 10, 1))

      assert_difference -> { @list.items.count }, 1 do
        post tool_todo_item_completion_path(@tool, @item), headers: @headers, as: :json
        post tool_todo_item_completion_path(@tool, @item), headers: @headers, as: :json
      end

      assert_response :success
      assert_equal Date.new(2026, 10, 8), @list.items.pending.find_by!(title: "Buy groceries").due_date
    end

    test "completing someone's item notifies them" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")
      @item.update!(assigned_user: user_two)

      assert_difference -> { user_two.notifications.count }, 1 do
        post tool_todo_item_completion_path(@tool, @item), headers: @headers, as: :json
      end

      assert_kind_of TodoCompletedNotifier, user_two.notifications.last.event
    end

    test "position moves an item to another list" do
      backlog = todo_lists(:backlog)
      backlog.items.create!(title: "Someday", position: 0)

      patch tool_todo_item_position_path(@tool, @item), params: { todo_list_id: backlog.id, position: 0 }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Backlog", response.parsed_body.dig("list", "title")
      assert_equal backlog.id, response.parsed_body["todo_list_id"]
      assert_equal [ "Buy groceries", "Someday" ], backlog.items.reload.map(&:title)
      assert_equal [ 0, 1 ], backlog.items.map(&:position)
    end

    test "position without a position moves the item to the bottom" do
      backlog = todo_lists(:backlog)
      backlog.items.create!(title: "Someday", position: 0)

      patch tool_todo_item_position_path(@tool, @item), params: { todo_list_id: backlog.id }, headers: @headers, as: :json

      assert_response :success
      assert_equal [ "Someday", "Buy groceries" ], backlog.items.reload.map(&:title)
    end

    test "position counts open items before completed ones" do
      @item.update!(completed_at: 1.hour.ago)
      @list.items.create!(title: "Walk dog", position: 4)
      watering = @list.items.create!(title: "Water plants", position: 5)

      patch tool_todo_item_position_path(@tool, watering), params: { position: 1 }, headers: @headers, as: :json

      assert_response :success
      assert_equal 1, response.parsed_body["position"]
      assert_equal [ "Call dentist", "Water plants", "Walk dog" ], @list.items.pending.map(&:title)
    end

    test "position refuses a list from another tool" do
      other_list = other_todos_tool.todo_lists.first

      patch tool_todo_item_position_path(@tool, @item), params: { todo_list_id: other_list.id }, headers: @headers, as: :json

      assert_response :not_found
      assert_equal @list, @item.reload.list
    end

    test "items and lists of another tool are not found through this tool" do
      other_list = other_todos_tool.todo_lists.first
      other_item = other_list.items.create!(title: "Elsewhere")

      get tool_todo_item_path(@tool, other_item), headers: @headers
      assert_response :not_found
      assert_equal "Not found", response.parsed_body["error"]

      patch tool_todo_item_path(@tool, other_item), params: { item: { title: "Taken" } }, headers: @headers, as: :json
      assert_response :not_found

      delete tool_todo_item_path(@tool, other_item), headers: @headers, as: :json
      assert_response :not_found

      post tool_todo_item_completion_path(@tool, other_item), headers: @headers, as: :json
      assert_response :not_found

      post tool_todo_item_comments_path(@tool, other_item), params: { body: "Hi" }, headers: @headers, as: :json
      assert_response :not_found

      patch tool_todo_item_position_path(@tool, other_item), params: { position: 0 }, headers: @headers, as: :json
      assert_response :not_found

      patch tool_todo_list_path(@tool, other_list), params: { title: "Taken" }, headers: @headers, as: :json
      assert_response :not_found

      delete tool_todo_list_path(@tool, other_list), headers: @headers, as: :json
      assert_response :not_found

      assert_equal "Elsewhere", other_item.reload.title
      assert_not other_item.completed?
      assert_equal 0, other_item.comments.count
      assert_equal "To Do", other_list.reload.title
    end

    test "comments can be added and removed, and notify collaborators" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        post tool_todo_item_comments_path(@tool, @item), params: { body: "<p>On <strong>it</strong></p>" }, headers: @headers, as: :json
      end

      assert_response :created
      comment = response.parsed_body
      assert_equal "On it", comment["body"]
      assert_includes comment["body_html"], "<strong>it</strong>"
      assert_equal @user.id, comment.dig("user", "id")
      assert_kind_of TodoCommentNotifier, user_two.notifications.last.event

      delete tool_todo_item_comment_path(@tool, @item, comment["id"]), headers: @headers, as: :json
      assert_response :no_content
      assert_not ::Todos::Comment.exists?(comment["id"])
    end

    test "a blank comment returns errors" do
      post tool_todo_item_comments_path(@tool, @item), params: { body: "" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body["errors"].any?
    end

    test "collaborators cannot delete someone else's comment" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")
      comment = todo_comments(:first_comment)

      delete tool_todo_item_comment_path(@tool, @item, comment), headers: api_headers(user_two), as: :json

      assert_response :forbidden
      assert ::Todos::Comment.exists?(comment.id)
    end

    test "programs can't be attached to a todo" do
      file = Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/octet-stream", original_filename: "Setup.EXE")

      assert_no_difference -> { @item.attachments.count } do
        post tool_todo_item_attachments_path(@tool, @item), params: { file: file }, headers: @headers
      end
      assert_response :unprocessable_entity
      assert_equal [ "File type .exe is not allowed for security reasons" ], response.parsed_body["errors"]
    end

    test "several files can be attached at once" do
      files = %w[one.txt two.txt].map { |name| Rack::Test::UploadedFile.new(StringIO.new(name), "text/plain", original_filename: name) }
      sign_in_as @user

      assert_difference -> { @item.attachments.count }, 2 do
        post tool_todo_item_attachments_path(@tool, @item), params: { files: files }
      end

      assert_redirected_to tool_todo_item_path(@tool, @item)
    end

    test "attachments can be uploaded and removed" do
      file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")

      post tool_todo_item_attachments_path(@tool, @item), params: { file: file }, headers: @headers

      assert_response :created
      attachment = response.parsed_body
      assert_equal "notes.txt", attachment["filename"]
      assert_equal 5, attachment["file_size"]
      assert attachment["download_url"].present?

      delete tool_todo_item_attachment_path(@tool, @item, attachment["id"]), headers: @headers, as: :json
      assert_response :no_content
      assert_equal 0, @item.attachments.count
    end

    test "lists can be created, renamed and deleted" do
      post tool_todo_lists_path(@tool), params: { title: "Later" }, headers: @headers, as: :json
      assert_response :created
      list = response.parsed_body
      assert_equal "Later", list["title"]
      assert_equal 2, list["position"]

      patch tool_todo_list_path(@tool, list["id"]), params: { title: "Someday" }, headers: @headers, as: :json
      assert_response :success
      assert_equal "Someday", response.parsed_body["title"]

      delete tool_todo_list_path(@tool, list["id"]), headers: @headers, as: :json
      assert_response :no_content
      assert_not ::Todos::List.exists?(list["id"])
    end

    test "renaming a list to nothing returns errors" do
      patch tool_todo_list_path(@tool, @list), params: { title: "" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
      assert_equal "To Do", @list.reload.title
    end

    test "read-only tokens can read but not change todos" do
      headers = api_headers(@user, permission: "read")

      get tool_todo_path(@tool), headers: headers
      assert_response :success

      get tool_todo_item_path(@tool, @item), headers: headers
      assert_response :success

      post todo_list_items_path(@list), params: { item: { title: "Nope" } }, headers: headers, as: :json
      assert_response :forbidden

      post tool_todo_item_completion_path(@tool, @item), headers: headers, as: :json
      assert_response :forbidden

      patch tool_todo_item_path(@tool, @item), params: { item: { title: "Nope" } }, headers: headers, as: :json
      assert_response :forbidden

      assert_equal "Buy groceries", @item.reload.title
      assert_not @item.completed?
      assert_not ::Todos::Item.exists?(title: "Nope")
    end

    private

    def other_todos_tool
      Tool.create!(name: "Other Todos", tool_type: tool_types(:todos), owner: @user)
    end
  end
end
