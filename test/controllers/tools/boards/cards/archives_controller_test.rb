# frozen_string_literal: true

require "test_helper"

module Tools
  module Boards
    module Cards
      class ArchivesControllerTest < ActionDispatch::IntegrationTest
        setup do
          sign_in_as users(:one)
          @card = cards(:first_task)
          @tool = tools(:project_board)
        end

        test "an archived card says so, with an Undo that brings it back" do
          post tool_board_card_archive_path(@tool, @card)
          assert @card.reload.archived?

          follow_redirect!
          assert_select ".flash", text: /Card archived\./ do
            assert_select "form[action='#{tool_board_card_archive_path(@tool, @card)}'][data-flash-undo]" do
              assert_select "input[name=_method][value=delete]"
              assert_select "button[data-hotkey=z]", text: "Undo"
            end
          end

          delete tool_board_card_archive_path(@tool, @card)
          assert_not @card.reload.archived?
        end
      end
    end
  end
end
