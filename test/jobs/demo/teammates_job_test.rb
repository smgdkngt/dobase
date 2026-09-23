# frozen_string_literal: true

require "test_helper"

class Demo::TeammatesJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    create_demo_tool_types
    @visitor = in_demo_mode { Demo.create_visitor! }
    @marcus, @priya, @jake = Demo.teammates_of(@visitor).order(:id).to_a
    @chat_tool = @visitor.owned_tools.find_by!(name: "Team Chat")
    @board_tool = @visitor.owned_tools.find_by!(name: "Product Launch")
    @tasks_tool = @visitor.owned_tools.find_by!(name: "Launch Tasks")
    clear_enqueued_jobs
  end

  test "Marcus turns up in the chat and types" do
    in_demo_mode do
      assert_broadcast_on(ChatChannel.broadcasting_for(@chat_tool.chat), type: "typing", user_id: @marcus.id, user_name: "Marcus Rivera") do
        assert_broadcasts PresenceChannel.broadcasting_for(@chat_tool), 1 do
          play :type, "marcus"
        end
      end
    end

    here = broadcasts(PresenceChannel.broadcasting_for(@chat_tool)).map { |message| ActiveSupport::JSON.decode(message) }.last
    assert_equal({ "type" => "here", "context" => nil, "hello" => false, "tool_id" => @chat_tool.id }, here.slice("type", "context", "hello", "tool_id"))
    assert_equal({ "id" => @marcus.id, "name" => "Marcus Rivera", "initials" => "MR", "avatar_url" => nil }, here["user"])
  end

  test "Marcus welcomes the visitor in the chat, mentioning them" do
    in_demo_mode do
      assert_difference -> { @chat_tool.chat.messages.where(user: @marcus).count }, 1 do
        assert_difference -> { @visitor.notifications.count }, 1 do
          play :say, "marcus"
        end
      end
    end

    message = @chat_tool.chat.messages.where(user: @marcus).last
    assert_equal [ @visitor.id ], message.mentioned_user_ids
    assert_match "welcome to Moonshot Snacks", message.body.to_plain_text
    assert_equal "MentionNotifier", @visitor.notifications.last.event.type
  end

  test "Priya opens a card, then comments on it for the visitor" do
    card = @board_tool.board.cards.find_by!(title: "Design landing page")

    in_demo_mode do
      play :look, "priya"
      here = broadcasts(PresenceChannel.broadcasting_for(@board_tool)).map { |message| ActiveSupport::JSON.decode(message) }.last
      assert_equal "card:#{card.id}", here["context"]
      assert_equal @priya.id, here.dig("user", "id")

      assert_difference -> { card.comments.where(user: @priya).count }, 1 do
        play :comment, "priya"
      end
    end

    notification = @visitor.notifications.last
    assert_equal "MentionNotifier", notification.event.type
    assert_equal "Priya Patel mentioned you in a comment on Design landing page", notification.message
  end

  test "Jake hands the visitor a todo" do
    in_demo_mode do
      assert_difference -> { Todos::Item.where(list: @tasks_tool.todo_lists, assigned_user: @visitor).count }, 1 do
        play :hand_over, "jake"
      end
    end

    item = Todos::Item.where(list: @tasks_tool.todo_lists).find_by!(title: "Taste-test the new Orbit Rings batch")
    assert_equal 0, item.position
    assert_equal @jake, item.created_by
    assert_equal "TodoAssignmentNotifier", @visitor.notifications.last.event.type
    here = broadcasts(PresenceChannel.broadcasting_for(@tasks_tool)).map { |message| ActiveSupport::JSON.decode(message) }.last
    assert_equal "todo:#{item.id}", here["context"]
  end

  test "each beat queues the next, and the last one ends it" do
    in_demo_mode do
      assert_enqueued_with job: Demo::TeammatesJob, args: [ @visitor, 1 ] do
        Demo::TeammatesJob.perform_now(@visitor, 0)
      end
      clear_enqueued_jobs

      assert_no_enqueued_jobs only: Demo::TeammatesJob do
        Demo::TeammatesJob.perform_now(@visitor, Demo::TeammatesJob::SCRIPT.size - 1)
      end
    end
  end

  test "the whole script runs through" do
    before = @visitor.notifications.maximum(:id).to_i

    in_demo_mode do
      assert_difference -> { @chat_tool.chat.messages.where(user: @marcus).count } => 2, -> { Boards::Comment.where(user: @priya).count } => 1 do
        perform_enqueued_jobs(only: Demo::TeammatesJob) { Demo::TeammatesJob.start(@visitor) }
      end
    end

    assert_equal %w[MentionNotifier MentionNotifier TodoAssignmentNotifier MentionNotifier],
      @visitor.notifications.where("id > ?", before).order(:id).map { |notification| notification.event.type }
  end

  test "a teammate someone joined as is left to them" do
    @marcus.sessions.create!

    in_demo_mode do
      assert_no_difference -> { Chats::Message.count } do
        assert_no_broadcasts PresenceChannel.broadcasting_for(@chat_tool) do
          play :say, "marcus"
        end
      end
    end
  end

  test "a card the visitor deleted is skipped, and the script goes on" do
    @board_tool.board.cards.find_by!(title: "Design landing page").destroy!

    in_demo_mode do
      assert_no_difference -> { Boards::Comment.count } do
        assert_enqueued_jobs 1, only: Demo::TeammatesJob do
          play :comment, "priya"
        end
      end
    end
  end

  test "nothing happens once the visitor is gone" do
    Demo::TeammatesJob.start(@visitor)
    @visitor.owned_tools.destroy_all
    @visitor.destroy!

    in_demo_mode do
      assert_no_difference -> { Chats::Message.count } do
        perform_enqueued_jobs only: Demo::TeammatesJob
      end
    end
  end

  test "nothing happens outside demo mode" do
    assert_no_difference -> { Chats::Message.count } do
      assert_no_broadcasts PresenceChannel.broadcasting_for(@chat_tool) do
        assert_no_enqueued_jobs only: Demo::TeammatesJob do
          Demo::TeammatesJob.perform_now(@visitor, 1)
        end
      end
    end
  end

  private

  # Plays the script's first beat of this kind by this teammate
  def play(does, who)
    beat = Demo::TeammatesJob::SCRIPT.index { |step| step[:does] == does && step[:who] == who }
    Demo::TeammatesJob.perform_now(@visitor, beat)
  end
end
