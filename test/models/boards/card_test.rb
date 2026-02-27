# frozen_string_literal: true

require "test_helper"

module Boards
  class CardTest < ActiveSupport::TestCase
    test "belongs to a column" do
      card = cards(:first_task)
      assert_equal columns(:todo), card.column
    end

    test "validates title presence" do
      card = Boards::Card.new(column: columns(:todo), position: 10)
      assert_not card.valid?
      assert_includes card.errors[:title], "can't be blank"
    end

    test "validates color inclusion" do
      card = cards(:first_task)

      %w[red orange yellow green blue purple].each do |color|
        card.color = color
        assert card.valid?, "#{color} should be valid"
      end

      card.color = "invalid"
      assert_not card.valid?
      assert_includes card.errors[:color], "is not included in the list"
    end

    test "allows blank color" do
      card = cards(:first_task)
      card.color = nil
      assert card.valid?

      card.color = ""
      assert card.valid?
    end

    test "can be assigned to a user" do
      card = cards(:first_task)
      user = users(:one)

      card.assigned_user = user
      card.save!

      assert_equal user, card.reload.assigned_user
    end

    test "assigned_user is optional" do
      card = cards(:first_task)
      assert_nil card.assigned_user
      assert card.valid?
    end
  end
end
