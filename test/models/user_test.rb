require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "deleting an account leaves a tool that another owner still owns" do
    tool = tools(:shared_board)
    tool.collaborators.find_by(user: users(:two)).update!(role: "owner")

    users(:one).destroy!

    assert Tool.exists?(tool.id), "co-owned tool was destroyed with its creator"
    assert_equal users(:two), tool.reload.owner
  end

  test "deleting an account destroys a tool nobody else owns" do
    tool = tools(:shared_board)

    users(:one).destroy!

    assert_not Tool.exists?(tool.id)
  end
end
