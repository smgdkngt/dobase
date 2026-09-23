# frozen_string_literal: true

require "test_helper"

class Demo::CleanupJobTest < ActiveJob::TestCase
  setup { create_demo_tool_types }

  test "removes visitors of more than a day ago with their workspaces" do
    in_demo_mode do
      expired = travel_to(25.hours.ago) { Demo.create_visitor! }
      recent = Demo.create_visitor!
      expired_tool_ids = expired.owned_tools.ids
      # A teammate the visitor made co-owner doesn't keep the tool around
      board = expired.owned_tools.find_by!(name: "Product Launch")
      board.collaborators.find_by!(user: User.find_by!(email_address: "marcus@moonshot-snacks.com")).update!(role: "owner")

      Demo::CleanupJob.perform_now

      assert_not User.exists?(expired.id)
      assert_empty Tool.where(id: expired_tool_ids)
      assert User.exists?(recent.id)
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
        board.collaborators.create!(user: User.find_by!(email_address: "marcus@moonshot-snacks.com"), role: "owner")
        [ visitor, board ]
      end
      visitor.destroy!
      assert_equal "marcus@moonshot-snacks.com", board.reload.owner.email_address

      Demo::CleanupJob.perform_now

      assert_not Tool.exists?(board.id)
    end
  end

  test "does nothing outside demo mode" do
    visitor = in_demo_mode { travel_to(25.hours.ago) { Demo.create_visitor! } }

    Demo::CleanupJob.perform_now

    assert User.exists?(visitor.id)
  end
end
