# frozen_string_literal: true

require "test_helper"

class CollaboratorTest < ActiveSupport::TestCase
  setup do
    @collaborator = collaborators(:two_shared_board)
  end

  test "muted? returns false when muted_at is nil" do
    refute @collaborator.muted?
  end

  test "mute! sets muted_at to the current time" do
    travel_to Time.zone.local(2026, 5, 29, 9, 0) do
      @collaborator.mute!

      assert @collaborator.reload.muted?
      assert_equal Time.zone.local(2026, 5, 29, 9, 0), @collaborator.muted_at
    end
  end

  test "unmute! clears muted_at" do
    @collaborator.mute!

    @collaborator.unmute!

    assert_nil @collaborator.reload.muted_at
    refute @collaborator.muted?
  end

  test "muted scope returns only muted collaborators" do
    @collaborator.mute!

    assert_includes Collaborator.muted, @collaborator
    refute_includes Collaborator.unmuted, @collaborator
  end

  test "unmuted scope returns only collaborators without muted_at" do
    assert_includes Collaborator.unmuted, @collaborator

    @collaborator.mute!

    refute_includes Collaborator.unmuted, @collaborator
  end

  test "destroying a collaborator deletes their notifications about the tool" do
    removed = @collaborator.user
    about_tool = ChatMessageNotifier.with(message: "hi", sender: users(:one), tool: @collaborator.tool).deliver(removed)
    elsewhere = ChatMessageNotifier.with(message: "hi", sender: users(:one), tool: tools(:other_calendar)).deliver(removed)

    @collaborator.destroy

    assert_equal [ elsewhere ], removed.notifications.map(&:event)
    assert Noticed::Event.exists?(about_tool.id)
  end

  test "destroying a collaborator keeps other people's notifications about the tool" do
    event = ChatMessageNotifier.with(message: "hi", sender: @collaborator.user, tool: @collaborator.tool).deliver([ users(:one), @collaborator.user ])

    @collaborator.destroy

    assert_equal [ event ], users(:one).notifications.map(&:event)
  end

  test "destroying a collaborator hands back the todos they were assigned on that tool" do
    tool = tools(:my_todos)
    membership = tool.collaborators.create!(user: users(:two), role: "collaborator")
    mine = todo_items(:pending_one)
    mine.update!(assigned_user: users(:two))
    elsewhere = todo_items(:other_item)
    elsewhere.update!(assigned_user: users(:two))

    membership.destroy

    assert_nil mine.reload.assigned_user
    assert_equal users(:two), elsewhere.reload.assigned_user
  end

  test "destroying a collaborator hands back the cards they were assigned on that tool" do
    column = boards(:shared).columns.create!(name: "To Do", position: 0)
    card = column.cards.create!(title: "Shared card", position: 0)
    card.update!(assigned_user: users(:two))

    @collaborator.destroy

    assert_nil card.reload.assigned_user
  end
end
