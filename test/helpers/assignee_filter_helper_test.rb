# frozen_string_literal: true

require "test_helper"

class AssigneeFilterHelperTest < ActionView::TestCase
  include AssigneeFilterHelper

  setup do
    @me   = users(:one)
    @them = users(:two)
    @mine     = Struct.new(:assigned_user_id).new(@me.id)
    @theirs   = Struct.new(:assigned_user_id).new(@them.id)
    @orphan   = Struct.new(:assigned_user_id).new(nil)
    @records  = [ @mine, @theirs, @orphan ]
  end

  test "blank filter returns the records unchanged" do
    assert_equal @records, filter_by_assignee(@records, nil)
    assert_equal @records, filter_by_assignee(@records, "")
  end

  test "me filter keeps only records assigned to current_user" do
    assert_equal [ @mine ], filter_by_assignee(@records, "me")
  end

  test "unassigned filter keeps only records with nil assignee" do
    assert_equal [ @orphan ], filter_by_assignee(@records, "unassigned")
  end

  test "user id filter keeps only records assigned to that user" do
    assert_equal [ @theirs ], filter_by_assignee(@records, @them.id.to_s)
  end

  test "unknown filter values return the records unchanged" do
    assert_equal @records, filter_by_assignee(@records, "garbage")
  end

  test "assignee_filter_label describes the active filter" do
    collaborators = [ @them ]
    assert_equal "Assigned to me", assignee_filter_label("me", collaborators)
    assert_equal "Unassigned", assignee_filter_label("unassigned", collaborators)
    assert_equal "Assigned to #{@them.name}", assignee_filter_label(@them.id.to_s, collaborators)
    assert_nil assignee_filter_label(nil, collaborators)
    assert_nil assignee_filter_label("999999", collaborators)
  end

  private
    def current_user
      @me
    end
end
