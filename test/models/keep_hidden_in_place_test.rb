# frozen_string_literal: true

require "test_helper"

class KeepHiddenInPlaceTest < ActiveSupport::TestCase
  test "shown entries take the new order and hidden ones stay after the entry they followed" do
    assert_equal [ 5, 3, 4, 1, 2 ], KeepHiddenInPlace.call([ 1, 2, 3, 4, 5 ], [ 5, 3, 1 ])
  end

  test "hidden entries at the start stay at the start, in their order" do
    assert_equal [ 8, 9, 2, 1 ], KeepHiddenInPlace.call([ 8, 9, 1, 2 ], [ 2, 1 ])
  end

  test "entries moved in from elsewhere and nothing hidden" do
    assert_equal [ 7, 1, 2 ], KeepHiddenInPlace.call([ 1, 2 ], [ 7, 1 ])
    assert_equal [ 2, 1 ], KeepHiddenInPlace.call([ 1, 2 ], [ 2, 1 ])
  end
end
