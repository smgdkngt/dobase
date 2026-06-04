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

    test "assigned_to scopes to items owned by the given user" do
      item = todo_items(:pending_one)
      item.update!(assigned_user: users(:two))

      assigned = Todos::Item.assigned_to(users(:two))

      assert_includes assigned, item
      refute_includes Todos::Item.assigned_to(users(:one)), item
    end

    test "unassigned scopes to items with no assignee" do
      todo_items(:pending_one).update!(assigned_user: users(:one))
      orphan = todo_items(:pending_two)

      unassigned = Todos::Item.unassigned

      assert_includes unassigned, orphan
      refute_includes unassigned, todo_items(:pending_one)
    end

    test "recurrence_rule must be one of the allowed values" do
      item = todo_items(:pending_one)

      %w[daily weekly monthly].each do |rule|
        item.recurrence_rule = rule
        assert item.valid?, "#{rule} should be a valid recurrence rule"
      end

      item.recurrence_rule = "hourly"
      refute item.valid?
      assert_includes item.errors[:recurrence_rule], "is not included in the list"
    end

    test "recurring? reflects the presence of a recurrence_rule" do
      item = todo_items(:pending_one)

      refute item.recurring?

      item.update!(recurrence_rule: "weekly")

      assert item.recurring?
    end

    test "spawn_next_instance creates a new item with the schedule advanced" do
      item = todo_items(:pending_one)
      item.update!(recurrence_rule: "daily", due_date: Date.current, assigned_user: users(:one))

      new_item = nil
      assert_difference -> { item.list.items.count }, 1 do
        new_item = item.spawn_next_instance!
      end

      assert_equal item.title, new_item.title
      assert_equal item.list, new_item.list
      assert_equal users(:one), new_item.assigned_user
      assert_equal "daily", new_item.recurrence_rule
      assert_equal Date.current + 1.day, new_item.due_date
      assert_nil new_item.completed_at
    end

    test "spawn_next_instance rolls the due_date forward by the rule's interval" do
      item = todo_items(:pending_one)
      anchor = Date.new(2026, 1, 15)

      { "daily" => anchor + 1.day, "weekly" => anchor + 1.week, "monthly" => anchor + 1.month }.each do |rule, expected|
        item.update!(recurrence_rule: rule, due_date: anchor)
        assert_equal expected, item.spawn_next_instance!.due_date,
          "#{rule} should advance due_date to #{expected}"
      end
    end

    test "spawn_next_instance leaves due_date nil when the item had none" do
      item = todo_items(:pending_one)
      item.update!(recurrence_rule: "weekly", due_date: nil)

      assert_nil item.spawn_next_instance!.due_date
    end

    test "spawn_next_instance does nothing for non-recurring items" do
      item = todo_items(:pending_one)
      assert_nil item.recurrence_rule

      assert_no_difference -> { item.list.items.count } do
        assert_nil item.spawn_next_instance!
      end
    end

    test "spawn_next_instance copies the rich-text description" do
      item = todo_items(:pending_one)
      item.update!(recurrence_rule: "daily", description: "<p>Take out the trash</p>")

      new_item = item.spawn_next_instance!

      assert_includes new_item.description.body.to_s, "Take out the trash"
    end
  end
end
