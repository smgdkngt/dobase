# frozen_string_literal: true

require "test_helper"

module Tools
  class BoardsApiTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @headers = api_headers(@user)
      @tool = tools(:project_board)
      @card = cards(:first_task)
    end

    test "board lists columns with their active cards" do
      cards(:second_task).update!(archived_at: Time.current)

      get tool_board_path(@tool), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal @tool.id, body.dig("tool", "id")
      assert_equal [ "To Do", "In Progress", "Done" ], body["columns"].map { |column| column["name"] }

      todo = body["columns"].first
      assert_equal [ "First task" ], todo["cards"].map { |card| card["title"] }
      assert_equal tool_board_url(@tool, card: @card.id), todo["cards"].first["url"]
    end

    test "board with archived=true lists only archived cards" do
      cards(:second_task).update!(archived_at: Time.current)

      get tool_board_path(@tool, archived: true), headers: @headers

      titles = response.parsed_body["columns"].flat_map { |column| column["cards"] }.map { |card| card["title"] }
      assert_equal [ "Second task" ], titles
    end

    test "board is forbidden for tools the user can't access" do
      get tool_board_path(@tool), headers: api_headers(users(:two))

      assert_response :forbidden
    end

    test "card shows description, column, comments and attachments" do
      @card.update!(description: "<p>Description of first task</p>")
      @card.comments.create!(user: users(:one), body: "<p>Looks <strong>good</strong></p>")

      get tool_board_card_path(@tool, @card), headers: @headers

      assert_response :success
      body = response.parsed_body
      assert_equal "Description of first task", body["description"]
      assert_equal "To Do", body.dig("column", "name")
      assert_equal "Looks good", body["comments"].first["body"]
      assert_includes body["comments"].first["body_html"], "<strong>good</strong>"
      assert_equal @user.email_address, body["comments"].first.dig("user", "email_address")
      assert_equal [], body["attachments"]
    end

    test "rich text HTML comes back sanitized" do
      @card.update!(description: %(<p>Hi <img src="x" onerror="alert(1)"><a href="javascript:alert(2)">link</a></p>))

      get tool_board_card_path(@tool, @card), headers: @headers

      html = response.parsed_body["description_html"]
      assert_includes html, "<p>Hi"
      assert_not_includes html, "onerror"
      assert_not_includes html, "javascript:"
    end

    test "create adds a card with all attributes and notifies the assignee" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")

      assert_difference -> { user_two.notifications.count }, 1 do
        post column_cards_path(columns(:todo)), headers: @headers, as: :json, params: {
          card: { title: "Ship API", description: "<p>With a CLI</p>", color: "green", due_date: "2026-10-01", assigned_user_id: user_two.id }
        }
      end

      assert_response :created
      body = response.parsed_body
      assert_equal "Ship API", body["title"]
      assert_equal "With a CLI", body["description"]
      assert_equal "green", body["color"]
      assert_equal "2026-10-01", body["due_date"]
      assert_equal user_two.id, body.dig("assignee", "id")
      assert_equal columns(:todo).cards.maximum(:position), body["position"]
    end

    test "create without a title returns errors" do
      post column_cards_path(columns(:todo)), params: { card: { title: "" } }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Title can't be blank"
    end

    test "update returns the card" do
      patch tool_board_card_path(@tool, @card), params: { card: { title: "Renamed", due_date: "" } }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Renamed", response.parsed_body["title"]
      assert_nil response.parsed_body["due_date"]
    end

    test "update refuses an assignee who isn't on the board" do
      assert_no_difference -> { Noticed::Notification.count } do
        patch tool_board_card_path(@tool, @card), params: { card: { assigned_user_id: users(:two).id } }, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body["errors"], "Assigned user must be a collaborator on this tool"
    end

    test "create refuses an assignee who isn't on the board" do
      assert_no_difference -> { ::Boards::Card.count } do
        post column_cards_path(columns(:todo)), params: { card: { title: "Harvest", assigned_user_id: users(:two).id } }, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
    end

    test "position moves a card to another column" do
      patch tool_board_card_position_path(@tool, @card), params: { column_id: columns(:done).id, position: 0 }, headers: @headers, as: :json

      assert_response :success
      assert_equal "Done", response.parsed_body.dig("column", "name")
      assert_equal [ "First task", "Completed task" ], columns(:done).cards.reload.map(&:title)
      assert_equal [ 0, 1 ], columns(:done).cards.map(&:position)
    end

    test "position without a position moves the card to the bottom" do
      patch tool_board_card_position_path(@tool, @card), params: { column_id: columns(:done).id }, headers: @headers, as: :json

      assert_equal [ "Completed task", "First task" ], columns(:done).cards.reload.map(&:title)
    end

    test "position reorders within the same column" do
      patch tool_board_card_position_path(@tool, cards(:second_task)), params: { position: 0 }, headers: @headers, as: :json

      assert_equal [ "Second task", "First task" ], columns(:todo).cards.reload.map(&:title)
    end

    test "position refuses a column from another board" do
      other_column = boards(:shared).columns.create!(name: "Elsewhere")

      patch tool_board_card_position_path(@tool, @card), params: { column_id: other_column.id }, headers: @headers, as: :json

      assert_response :not_found
      assert_equal columns(:todo), @card.reload.column
    end

    test "position notifies the assignee when the card changes column" do
      user_two = users(:two)
      @tool.collaborators.create!(user: user_two, role: "collaborator")
      @card.update!(assigned_user: user_two)

      assert_difference -> { user_two.notifications.count }, 1 do
        patch tool_board_card_position_path(@tool, @card), params: { column_id: columns(:done).id }, headers: @headers, as: :json
      end
    end

    test "archive and unarchive return the card" do
      post tool_board_card_archive_path(@tool, @card), headers: @headers, as: :json
      assert_response :success
      assert response.parsed_body["archived"]

      delete tool_board_card_archive_path(@tool, @card), headers: @headers, as: :json
      assert_response :success
      assert_not response.parsed_body["archived"]
    end

    test "destroy returns no content" do
      delete tool_board_card_path(@tool, @card), headers: @headers, as: :json

      assert_response :no_content
      assert_not ::Boards::Card.exists?(@card.id)
    end

    test "comments can be added and removed" do
      post tool_board_card_comments_path(@tool, @card), params: { body: "On it" }, headers: @headers, as: :json

      assert_response :created
      assert_equal "On it", response.parsed_body["body"]

      delete tool_board_card_comment_path(@tool, @card, response.parsed_body["id"]), headers: @headers, as: :json
      assert_response :no_content
      assert_equal 0, @card.comments.count
    end

    test "a blank comment returns errors" do
      post tool_board_card_comments_path(@tool, @card), params: { body: "" }, headers: @headers, as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body["errors"].any?
    end

    test "attachments can be uploaded" do
      file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")

      post tool_board_card_attachments_path(@tool, @card), params: { file: file }, headers: @headers

      assert_response :created
      assert_equal "notes.txt", response.parsed_body["filename"]
      assert response.parsed_body["download_url"].present?
    end

    test "programs can't be attached, and nothing is saved when one of the files is refused" do
      files = [
        Rack::Test::UploadedFile.new(StringIO.new("fine"), "text/plain", original_filename: "notes.txt"),
        Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/x-msdownload", original_filename: "setup.exe")
      ]
      sign_in_as @user

      assert_no_difference -> { @card.attachments.count } do
        post tool_board_card_attachments_path(@tool, @card), params: { files: files }
      end
      assert_redirected_to tool_board_card_path(@tool, @card)
      assert_equal "File type .exe is not allowed for security reasons", flash[:alert]
    end

    test "the API says why an attachment was refused" do
      file = Rack::Test::UploadedFile.new(StringIO.new("echo hi"), "application/x-sh", original_filename: "run")

      post tool_board_card_attachments_path(@tool, @card), params: { file: file }, headers: @headers

      assert_response :unprocessable_entity
      assert_equal [ "File type is not allowed for security reasons" ], response.parsed_body["errors"]
    end

    test "several files can be attached at once" do
      files = %w[one.txt two.txt].map { |name| Rack::Test::UploadedFile.new(StringIO.new(name), "text/plain", original_filename: name) }

      sign_in_as @user

      assert_difference -> { @card.attachments.count }, 2 do
        post tool_board_card_attachments_path(@tool, @card), params: { files: files }
      end

      assert_redirected_to tool_board_card_path(@tool, @card)
      assert_equal %w[one.txt two.txt], @card.attachments.order(:id).pluck(:filename)
    end

    test "columns can be created, renamed and deleted" do
      post tool_board_columns_path(@tool), params: { name: "Review" }, headers: @headers, as: :json
      assert_response :created
      column_id = response.parsed_body["id"]
      assert_equal "Review", response.parsed_body["name"]

      patch tool_board_column_path(@tool, column_id), params: { name: "QA" }, headers: @headers, as: :json
      assert_response :success
      assert_equal "QA", response.parsed_body["name"]

      delete tool_board_column_path(@tool, column_id), headers: @headers, as: :json
      assert_response :no_content
    end

    test "read-only tokens can read but not change the board" do
      headers = api_headers(@user, permission: "read")

      get tool_board_card_path(@tool, @card), headers: headers
      assert_response :success

      patch tool_board_card_path(@tool, @card), params: { card: { title: "Nope" } }, headers: headers, as: :json
      assert_response :forbidden
      assert_equal "First task", @card.reload.title
    end
  end
end
