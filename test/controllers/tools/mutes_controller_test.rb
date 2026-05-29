# frozen_string_literal: true

require "test_helper"

module Tools
  class MutesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tool = tools(:shared_board)
      @user = users(:two)
      sign_in_as @user
    end

    test "create mutes the current user's collaborator record" do
      collaborator = collaborators(:two_shared_board)
      refute collaborator.muted?

      post tool_mute_path(@tool)

      assert_redirected_to edit_tool_path(@tool)
      assert collaborator.reload.muted?
    end

    test "destroy unmutes the current user's collaborator record" do
      collaborator = collaborators(:two_shared_board)
      collaborator.mute!

      delete tool_mute_path(@tool)

      assert_redirected_to edit_tool_path(@tool)
      refute collaborator.reload.muted?
    end

    test "outsider cannot mute a tool they don't have access to" do
      private_tool = tools(:project_board)

      post tool_mute_path(private_tool)

      assert_redirected_to root_path
      assert_equal "You don't have access to this tool.", flash[:alert]
    end
  end
end
