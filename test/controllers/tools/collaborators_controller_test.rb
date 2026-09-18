# frozen_string_literal: true

require "test_helper"

module Tools
  class CollaboratorsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tool = tools(:shared_board)
      @card = boards(:shared).columns.create!(name: "Doing", position: 0).cards.create!(title: "Secret launch plan", position: 0)
      CardAssignmentNotifier.with(card: @card, assigner: users(:one), tool: @tool).deliver(users(:two))
    end

    test "a removed collaborator no longer sees the tool's cards in their notifications" do
      sign_in_as users(:one)
      delete tool_collaborator_path(@tool, collaborators(:two_shared_board))

      sign_in_as users(:two)
      get notifications_path

      assert_response :success
      assert_not_includes response.body, @card.title
    end

    test "leaving a tool you created hands it over to the remaining owner" do
      collaborators(:two_shared_board).update!(role: "owner")
      sign_in_as users(:one)

      delete leave_tool_collaborators_path(@tool)

      assert_equal users(:two), @tool.reload.owner
    end

    test "a collaborator who leaves no longer sees the tool's cards in their notifications" do
      sign_in_as users(:two)
      get notifications_path
      assert_includes response.body, @card.title

      delete leave_tool_collaborators_path(@tool)
      get notifications_path

      assert_not_includes response.body, @card.title
    end
  
    test "inviting someone again after their invitation expired sends a fresh one" do
      expired = @tool.invitations.create!(email: "newcomer@example.com", invited_by: users(:one))
      expired.update_column(:expires_at, 1.day.ago)
      sign_in_as users(:one)

      post tool_collaborators_path(@tool), params: { email: "newcomer@example.com" }

      assert_redirected_to edit_tool_path(@tool, tab: "collaborators")
      assert_equal "Invitation sent to newcomer@example.com.", flash[:notice]
      assert @tool.invitations.active.exists?(email: "newcomer@example.com")
    end

    test "reinviting from a stale declined row says so instead of erroring" do
      declined = @tool.invitations.create!(email: "newcomer@example.com", invited_by: users(:one), status: "declined")
      @tool.invitations.create!(email: "newcomer@example.com", invited_by: users(:one))
      sign_in_as users(:one)

      post tool_resend_invitation_path(@tool, declined)

      assert_redirected_to edit_tool_path(@tool, tab: "collaborators")
      assert_equal "declined", declined.reload.status
    end
  end
end
