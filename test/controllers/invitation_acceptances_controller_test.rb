# frozen_string_literal: true

require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tool = Tool.create!(name: "Launch Plan", tool_type: tool_types(:board), owner: users(:one))
  end

  test "the invited account accepts and joins the tool" do
    invitation = invite("two@example.com")
    sign_in_as users(:two)

    post invitation_acceptance_path(token: invitation.token)

    assert_redirected_to tool_path(@tool)
    assert @tool.accessible_by?(users(:two))
    assert_equal "accepted", invitation.reload.status
  end

  test "another account can't use the invitation" do
    invitation = invite("someone@example.com")
    sign_in_as users(:two)

    get invitation_acceptance_path(token: invitation.token)
    assert_response :success
    assert_includes response.body, "This invitation is for <strong>someone@example.com</strong>"
    assert_select "button", text: "Accept Invitation", count: 0

    post invitation_acceptance_path(token: invitation.token)

    assert_redirected_to invitation_acceptance_path(token: invitation.token)
    assert_not @tool.accessible_by?(users(:two))
    assert_equal "pending", invitation.reload.status
  end

  private

  def invite(email)
    @tool.invitations.create!(email: email, invited_by: users(:one))
  end
end
