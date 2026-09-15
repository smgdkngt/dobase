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

    test "a collaborator who leaves no longer sees the tool's cards in their notifications" do
      sign_in_as users(:two)
      get notifications_path
      assert_includes response.body, @card.title

      delete leave_tool_collaborators_path(@tool)
      get notifications_path

      assert_not_includes response.body, @card.title
    end
  end
end
