# frozen_string_literal: true

require "test_helper"

class ToolPresenceTest < ActiveSupport::TestCase
  setup { ToolPresence.reset! }

  test "only the first tab arrives and only the last one leaves" do
    assert ToolPresence.connect(1, 7)
    assert_not ToolPresence.connect(1, 7)

    assert_not ToolPresence.disconnect(1, 7)
    assert ToolPresence.disconnect(1, 7)
  end

  test "a connection this process never counted doesn't announce a departure" do
    assert_not ToolPresence.disconnect(1, 7)
  end
end
