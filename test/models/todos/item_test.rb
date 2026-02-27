# frozen_string_literal: true

require "test_helper"

module Todos
  class ItemTest < ActiveSupport::TestCase
    test "belongs to list" do
      item = todo_items(:pending_one)
      assert_equal todo_lists(:main), item.list
    end

    test "validates title presence" do
      item = Todos::Item.new(list: todo_lists(:main))
      assert_not item.valid?
      assert item.errors[:title].any?
    end

    test "pending scope returns items without completed_at" do
      pending = todo_lists(:main).items.pending
      assert pending.include?(todo_items(:pending_one))
      assert pending.include?(todo_items(:pending_two))
      assert_not pending.include?(todo_items(:recently_completed))
      assert_not pending.include?(todo_items(:old_completed))
    end

    test "recently_completed scope returns items completed within 24 hours" do
      recent = todo_lists(:main).items.recently_completed
      assert recent.include?(todo_items(:recently_completed))
      assert_not recent.include?(todo_items(:old_completed))
      assert_not recent.include?(todo_items(:pending_one))
    end

    test "completed_hidden scope returns items completed more than 24 hours ago" do
      hidden = todo_lists(:main).items.completed_hidden
      assert hidden.include?(todo_items(:old_completed))
      assert_not hidden.include?(todo_items(:recently_completed))
      assert_not hidden.include?(todo_items(:pending_one))
    end

    test "completed? returns true when completed_at is set" do
      assert todo_items(:recently_completed).completed?
      assert_not todo_items(:pending_one).completed?
    end

    test "visible scope returns pending and recently completed" do
      visible = todo_lists(:main).items.visible
      assert visible.include?(todo_items(:pending_one))
      assert visible.include?(todo_items(:recently_completed))
      assert_not visible.include?(todo_items(:old_completed))
    end
  end
end
