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

  test "a file added says what it is called, where it is and how big" do
    tool = tools(:my_files)
    item = nil

    events = events_of do
      item = tool.file_items.new(name: "notes.txt", folder: file_folders(:documents))
      item.file.attach(io: StringIO.new("hello"), filename: "notes.txt", content_type: "text/plain")
      item.save!
      item.update!(name: "renamed.txt")
    end

    assert_equal [ [ "file.created", item.id, { "name" => "notes.txt", "folder" => file_folders(:documents).name, "size" => 5 } ] ], summary(events)
    assert_equal tool.id, events.sole.tool_id
  end

  test "an appointment made, changed and removed" do
    calendar = calendars_calendars(:personal)
    event = nil
    starts = Time.utc(2030, 1, 10, 9)

    made = events_of { event = calendar.events.create!(uid: "lunch@test", summary: "Lunch", location: "Cafe", starts_at: starts, ends_at: starts + 1.hour) }
    assert_equal [ [ "calendar.event_created", event.id, { "title" => "Lunch", "starts_at" => "2030-01-10T09:00:00Z", "ends_at" => "2030-01-10T10:00:00Z",
      "all_day" => false, "location" => "Cafe", "calendar" => "Personal" } ] ], summary(made)
    assert_equal tools(:my_calendar).id, made.sole.tool_id

    changed = events_of do
      event.update!(starts_at: starts + 1.hour, ends_at: starts + 2.hours)
      event.update!(summary: "Long lunch", location: "Park")
      event.update!(calendar: calendars_calendars(:work))
    end
    assert_equal [ %w[starts_at ends_at], %w[title location], %w[calendar] ], changed.map { |change| change.data["changed"] }
    assert_equal %w[calendar.event_updated], changed.map(&:kind).uniq

    removed = events_of { event.destroy! }
    assert_equal [ [ "calendar.event_deleted", event.id, "Long lunch", "Work" ] ], removed.map { |change| [ change.kind, change.record_id, change.data["title"], change.data["calendar"] ] }
  end

  test "an appointment saved without a change to when, what or where is no event" do
    event = calendars_events(:meeting)

    events = events_of do
      event.update!(summary: event.summary)
      event.update!(etag: "new-etag", description: "Another agenda", attendees: [ { "email" => "ann@example.com" } ])
    end

    assert_empty events
  end

  test "a calendar that goes takes its appointments along without a word" do
    calendar = calendars_calendars(:personal)
    assert_operator calendar.events.count, :>, 0

    assert_empty events_of { calendar.destroy! }
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
