# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260918120000_move_sidebar_position_to_collaborators")

class MoveSidebarPositionToCollaboratorsTest < ActiveSupport::TestCase
  setup do
    @shared = tools(:shared_board)
    @docs = tools(:my_docs)
    migrate :down
  end

  teardown do
    migrate :up unless column_exists?(:collaborators, :sidebar_position)
  end

  test "everybody keeps the order the shared column gave them" do
    set_shared_position @shared, 2
    set_shared_position @docs, 5

    migrate :up

    assert_equal 2, position_for(users(:one), @shared)
    assert_equal 2, position_for(users(:two), @shared)
    assert_equal 5, position_for(users(:one), @docs)
  end

  test "rolling back keeps the order of the tool's owner" do
    migrate :up
    Collaborator.where(tool_id: @shared.id).find_each do |collaborator|
      collaborator.update_column(:sidebar_position, collaborator.user_id == @shared.owner_id ? 3 : 9)
    end

    migrate :down

    assert_equal 3, shared_position(@shared)
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { MoveSidebarPositionToCollaborators.new.public_send(direction) }
    Tool.reset_column_information
    Collaborator.reset_column_information
  end

  def column_exists?(table, column)
    ActiveRecord::Base.connection.column_exists?(table, column)
  end

  def set_shared_position(tool, position)
    Tool.where(id: tool.id).update_all(sidebar_position: position)
  end

  def shared_position(tool)
    Tool.where(id: tool.id).pick(:sidebar_position)
  end

  def position_for(user, tool)
    Collaborator.where(user_id: user.id, tool_id: tool.id).pick(:sidebar_position)
  end
end
