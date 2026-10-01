# frozen_string_literal: true

require "test_helper"

class WorkspaceSearchTest < ActiveSupport::TestCase
  test "finds a card, and links to the board with the card open" do
    hit = search(users(:one), "First task").find { |h| h.kind == :card }

    assert_equal "First task", hit.title
    assert_equal "/tools/#{tools(:project_board).id}/board?card=#{cards(:first_task).id}", hit.path
  end

  test "finds a document by what's written in it, with the words around the match" do
    docs_documents(:meeting_notes).update!(content: "<p>We agreed to ship the gamma release on Friday after lunch.</p>")

    hit = search(users(:one), "gamma release").find { |h| h.kind == :document }

    assert_equal "Meeting Notes", hit.title
    assert_includes hit.excerpt, "gamma release"
  end

  test "never finds anything in a tool you aren't on" do
    outsider = User.create!(first_name: "Out", last_name: "Sider", email_address: "outsider-search@example.com", password: "password123")

    assert_empty search(outsider, "First task")
    assert_empty search(outsider, "Meeting")
  end

  test "a colleague finds what's in a tool shared with them" do
    column = boards(:shared).columns.create!(name: "Doing", position: 0)
    column.cards.create!(title: "Quarterly zebra review", position: 0)

    assert_equal [ "Quarterly zebra review" ], search(users(:two), "zebra").map(&:title)
  end

  test "a percent sign is looked for, not treated as a wildcard" do
    assert_empty search(users(:one), "%%")
  end

  test "an underscore is looked for, not treated as any character" do
    tool = tools(:my_files)
    Files::Item.create!(tool: tool, name: "IMG_1234.jpg")
    Files::Item.create!(tool: tool, name: "IMGX1234.jpg")
    Files::Folder.create!(tool: tool, name: "raw_scans")

    assert_equal [ "IMG_1234.jpg" ], search(users(:one), "IMG_1234").map(&:title)
    assert_equal [ "raw_scans" ], search(users(:one), "raw_scans").map(&:title)
  end

  test "a percent sign in the middle of a search finds itself" do
    column = boards(:shared).columns.create!(name: "Doing", position: 0)
    column.cards.create!(title: "Budget is 50% spent", position: 0)
    column.cards.create!(title: "Budget is 500 spent", position: 1)
    todo_lists(:main).items.create!(title: "Ask for 50% off", position: 9)

    assert_equal [ "Budget is 50% spent", "Ask for 50% off" ], search(users(:one), "50%").map(&:title)
  end

  test "an underscore finds a chat message and a document that have one" do
    docs_documents(:meeting_notes).update!(content: "<p>Set APP_HOST before deploying.</p>")
    chat_type = ToolType.find_by(slug: "chat") || ToolType.create!(slug: "chat", name: "Chat", icon: "message-circle")
    chat = Tool.create!(name: "Team Chat", tool_type: chat_type, owner: users(:one)).chat
    chat.messages.create!(user: users(:one), body: "<p>APP_HOST is wrong on staging</p>")
    chat.messages.create!(user: users(:one), body: "<p>APPXHOST is something else</p>")

    hits = search(users(:one), "APP_HOST")

    assert_equal %i[document message], hits.map(&:kind)
    assert_includes hits.last.excerpt, "APP_HOST is wrong"
  end

  test "one letter isn't enough to search on" do
    assert_not WorkspaceSearch.new(users(:one), "a").searchable?
    assert_empty search(users(:one), "a")
  end

  test "an archived card stays out of the results" do
    cards(:first_task).update!(archived_at: Time.current)

    assert_not_includes search(users(:one), "First task").map(&:title), "First task"
  end

  test "open todos come before finished ones" do
    list = tools(:my_todos).todo_lists.first
    list.items.create!(title: "Zeta finished", position: 0, completed_at: Time.current)
    list.items.create!(title: "Zeta open", position: 1)

    todos = search(users(:one), "Zeta").select { |hit| hit.kind == :todo }.map(&:title)

    assert_equal [ "Zeta open", "Zeta finished" ], todos
  end

  test "a word that only appears inside the HTML of a text doesn't count as a match" do
    docs_documents(:meeting_notes).update!(content: %(<p>See <a href="https://example.com">the plan</a>.</p>))

    assert_not search(users(:one), "href").any? { |hit| hit.kind == :document }
    assert search(users(:one), "the plan").any? { |hit| hit.kind == :document }
  end

  private

  def search(user, query)
    WorkspaceSearch.new(user, query).hits
  end
end
