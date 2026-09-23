# frozen_string_literal: true

require "test_helper"

class Demo::CleanupJobTest < ActiveJob::TestCase
  setup { create_demo_tool_types }

  test "removes visitors of more than a day ago with their teammates and workspaces" do
    in_demo_mode do
      expired = travel_to(25.hours.ago) { Demo.create_visitor! }
      recent = Demo.create_visitor!
      expired_party_ids = Demo.party_of(expired).ids
      expired_tool_ids = expired.owned_tools.ids
      marcus = Demo.teammates_of(expired).find_by!(first_name: "Marcus")
      # A teammate the visitor made co-owner doesn't keep the tool around
      board = expired.owned_tools.find_by!(name: "Product Launch")
      board.collaborators.find_by!(user: marcus).update!(role: "owner")
      # Nor does a tool someone made while joined as a teammate
      side_project = Tool.create!(name: "Side project", tool_type: tool_types(:board), owner: marcus)

      Demo::CleanupJob.perform_now

      assert_equal 4, expired_party_ids.size
      assert_empty User.where(id: expired_party_ids)
      assert_empty Tool.where(id: expired_tool_ids)
      assert_not Tool.exists?(side_project.id)
      assert_equal 4, Demo.party_of(recent).count
      assert_equal 12, recent.owned_tools.count
      assert User.exists?(users(:one).id)
      assert Tool.exists?(tools(:my_files).id)
    end
  end

  test "removes what a visitor handed over to a teammate by deleting their account" do
    in_demo_mode do
      visitor, board = travel_to(25.hours.ago) do
        visitor = Demo.create_visitor!
        board = Tool.create!(name: "Side project", tool_type: tool_types(:board), owner: visitor)
        board.collaborators.create!(user: Demo.teammates_of(visitor).first, role: "owner")
        [ visitor, board ]
      end
      teammate_ids = Demo.teammates_of(visitor).ids
      visitor.destroy!
      assert_includes teammate_ids, board.reload.owner_id

      Demo::CleanupJob.perform_now

      assert_not Tool.exists?(board.id)
      assert_empty User.where(id: teammate_ids)
    end
  end

  test "clears up after the teammates every workspace used to share" do
    in_demo_mode do
      marcus, * = Demo::Workspace.teammates
      board = travel_to(25.hours.ago) { Tool.create!(name: "Handed over", tool_type: tool_types(:board), owner: marcus) }

      Demo::CleanupJob.perform_now

      assert_not Tool.exists?(board.id)
      assert User.exists?(marcus.id)
    end
  end

  test "does nothing outside demo mode" do
    visitor = in_demo_mode { travel_to(25.hours.ago) { Demo.create_visitor! } }

    Demo::CleanupJob.perform_now

    assert User.exists?(visitor.id)
    assert_equal 3, Demo.teammates_of(visitor).count
  end
end
