# frozen_string_literal: true

require "test_helper"

class Demo::WorkspaceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    create_demo_tool_types
    @owner = users(:one)
  end

  test "builds every kind of tool for its owner" do
    Demo::Workspace.new(@owner).build

    tools = @owner.owned_tools
    assert_equal %w[boards calendar chat docs files mail room todos], tools.joins(:tool_type).distinct.pluck("tool_types.slug").sort
    assert_equal tools.count, @owner.accessible_tools.count
    assert tools.all? { |tool| tool.owned_by?(@owner) }
    assert_equal [ "Launch", "Team" ], @owner.sidebar_groups.pluck(:name)
  end

  test "shares the team tools with the teammates" do
    Demo::Workspace.new(@owner).build

    board = @owner.owned_tools.find_by!(name: "Product Launch")
    marcus, priya, jake = Demo::Workspace.teammates
    [ marcus, priya, jake ].each { |teammate| assert board.accessible_by?(teammate) }
    assert_not board.owned_by?(marcus)
    assert_not @owner.owned_tools.find_by!(name: "Mail").accessible_by?(marcus)
  end

  test "fills the tools with examples dated from now" do
    travel_to Time.zone.local(2031, 5, 4, 12) do
      Demo::Workspace.new(@owner).build
    end

    board = @owner.owned_tools.find_by!(name: "Product Launch").board
    assert_equal 12, board.cards.count
    assert_equal Date.new(2031, 5, 9), board.cards.find_by!(title: "Write press release for launch day").due_date.to_date
    assert_equal 15, @owner.owned_tools.find_by!(name: "Team Chat").chat.messages.count
    assert_equal 8, @owner.owned_tools.find_by!(name: "Mail").mail_account.messages.count
    assert_equal 12, @owner.owned_tools.find_by!(name: "Team Files").file_items.count
    assert_operator @owner.owned_tools.find_by!(name: "Calendar").calendar_account.events.count, :>=, 17
  end

  test "makes the teammates once" do
    assert_difference -> { User.count }, 3 do
      Demo::Workspace.new(@owner).build
      Demo::Workspace.new(users(:two)).build
    end
  end

  test "reaches no server while building" do
    resolver = RemoteHost.resolver
    RemoteHost.resolver = ->(host) { flunk "looked up #{host}" }

    assert_no_enqueued_jobs only: [ SyncEmailsJob, SyncCalendarsJob, PushEventJob, ImapSyncJob, SyncDraftJob ] do
      Demo::Workspace.new(@owner).build
    end
  ensure
    RemoteHost.resolver = resolver
  end
end
