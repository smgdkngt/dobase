# frozen_string_literal: true

require "test_helper"

# A card, a comment on one and a chat message write their own events when they are
# saved (Event): whatever saves them, a request, a job or the console, is heard, and
# nothing that changes one can forget to say so. Here they are saved directly, with
# nobody signed in.
class EventsWrittenTest < ActiveSupport::TestCase
  setup do
    @board = tools(:project_board)
    @card = cards(:first_task)
  end

  test "a card made" do
    card = nil
    events = events_of { card = columns(:todo).cards.create!(title: "Harvest", position: 9) }

    assert_equal [ [ "card.created", card.id, { "title" => "Harvest", "column" => "To Do" } ] ], summary(events)
    assert_equal [ @board.id, nil ], events.sole.values_at(:tool_id, :user_id)
  end

  test "a card changed says what changed, each time it is saved" do
    events = events_of do
      @card.update!(title: "Renamed", description: "<p>More to it</p>")
      @card.update!(color: "red")
    end

    assert_equal [
      [ "card.updated", @card.id, { "title" => "Renamed", "column" => "To Do", "changed" => %w[title description] } ],
      [ "card.updated", @card.id, { "title" => "Renamed", "column" => "To Do", "changed" => %w[color] } ]
    ], summary(events)
  end

  test "a card made and then changed is both" do
    events = events_of { columns(:todo).cards.create!(title: "Harvest", position: 9).update!(title: "Harvest twice") }

    assert_equal %w[card.created card.updated], events.map(&:kind)
  end

  test "a card given to someone names them" do
    @board.collaborators.create!(user: users(:two))

    events = events_of { @card.update!(assigned_user: users(:two)) }

    assert_equal [ %w[assignee], users(:two).name ], events.sole.data.values_at("changed", "assignee")
  end

  test "a card saved as it was, or one that only changes places, is no event" do
    events = events_of do
      @card.update!(title: @card.title)
      @card.update!(position: 5, updated_by: users(:one))
      cards(:second_task).move_to(columns(:todo), position: 0)
    end

    assert_empty events
  end

  test "a card moved to another column says where it came from" do
    events = events_of { @card.move_to(columns(:done)) }

    assert_equal [ [ "card.moved", @card.id, { "title" => "First task", "column" => "Done", "moved_from" => "To Do" } ] ], summary(events)
  end

  test "a card archived and brought back" do
    events = events_of do
      @card.update!(archived_at: Time.current)
      @card.update!(archived_at: nil)
    end

    assert_equal [ [ "card.archived", @card.id ], [ "card.unarchived", @card.id ] ], events.map { |event| [ event.kind, event.record_id ] }
  end

  test "a card deleted, and the cards that go with a deleted column" do
    events = events_of { @card.destroy! }
    assert_equal [ [ "card.deleted", @card.id, { "title" => "First task", "column" => "To Do" } ] ], summary(events)

    left = columns(:todo).cards.pluck(:id)
    assert_not_empty left
    events = events_of { columns(:todo).destroy! }
    assert_equal [ [ "card.deleted", "To Do" ] ], events.map { |event| [ event.kind, event.data["column"] ] }.uniq
    assert_equal left.sort, events.map(&:record_id).sort
  end

  test "a tool that is deleted takes its cards along without a word" do
    assert_operator @board.board.cards.count, :>, 1

    assert_empty events_of { @board.destroy! }
    assert_not Boards::Card.exists?(@card.id)
  end

  test "a change that is taken back leaves no event" do
    events = events_of do
      Boards::Card.transaction do
        @card.update!(title: "Never happened")
        raise ActiveRecord::Rollback
      end
    end

    assert_empty events
  end

  test "a comment on a card, with its first words" do
    comment = nil
    events = events_of { comment = @card.comments.create!(user: users(:one), body: "<p>On it, <strong>today</strong></p>") }

    assert_equal [ [ "card.commented", @card.id, { "title" => "First task", "column" => "To Do", "comment_id" => comment.id, "excerpt" => "On it, today" } ] ], summary(events)
  end

  test "a chat message, with its first words and how many files" do
    chat_type = ToolType.find_or_create_by!(slug: "chat") { |tool_type| tool_type.assign_attributes(name: "Chat", icon: "messages-square") }
    chat = Tool.create!(name: "Team", tool_type: chat_type, owner: users(:one)).chat
    first = chat.messages.create!(user: users(:one), body: "<p>Lunch?</p>")

    events = events_of do
      chat.messages.create!(user: users(:one), reply_to: first, body: "<p>#{"Lunch is ready. " * 20}</p>",
        files: [ { io: StringIO.new("menu"), filename: "menu.txt", content_type: "text/plain" } ])
    end

    event = events.sole
    assert_equal [ "chat.message", chat.tool_id, chat.messages.last.id ], event.values_at(:kind, :tool_id, :record_id)
    assert_equal 140, event.data["excerpt"].length
    assert event.data["excerpt"].start_with?("Lunch is ready. Lunch")
    assert_equal [ 1, first.id ], event.data.values_at("files", "reply_to")
  end

  private
    def events_of
      before = Event.maximum(:id).to_i
      yield
      Event.where(id: (before + 1)..).order(:id).to_a
    end

    def summary(events)
      events.map { |event| [ event.kind, event.record_id, event.data ] }
    end
end
