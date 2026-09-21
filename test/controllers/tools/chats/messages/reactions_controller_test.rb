# frozen_string_literal: true

require "test_helper"

module Tools
  module Chats
    module Messages
      class ReactionsControllerTest < ActionDispatch::IntegrationTest
        include ActionCable::TestHelper

        setup do
          @user = users(:one)
          @other_user = users(:two)
          chat_type = ToolType.find_or_create_by!(slug: "chat") { |type| type.name = "Chat"; type.icon = "messages-square" }
          @tool = Tool.create!(name: "Team Chat", owner: @user, tool_type: chat_type)
          @tool.collaborators.create!(user: @other_user, role: "collaborator")
          @message = @tool.chat.messages.create!(user: @other_user, body: "<p>Standup at 2?</p>")
          sign_in_as @user
        end

        test "an emoji goes on a message once, and comes off again" do
          2.times { post tool_chat_message_reactions_path(@tool, @message), params: { emoji: "👍" } }
          assert_response :no_content
          assert_equal [ [ "👍", [ @user ] ] ], @message.reload.reaction_groups.to_a

          delete tool_chat_message_reaction_path(@tool, @message, "👍")
          assert_response :no_content
          assert_empty @message.reload.reactions
        end

        test "taking off an emoji only takes off your own" do
          @message.reactions.create!(user: @other_user, emoji: "🎉")

          delete tool_chat_message_reaction_path(@tool, @message, "🎉")

          assert_equal [ @other_user ], @message.reload.reaction_groups["🎉"]
        end

        test "only the emoji on offer" do
          post tool_chat_message_reactions_path(@tool, @message), params: { emoji: "<b>hi</b>" }

          assert_response :unprocessable_entity
          assert_empty @message.reload.reactions
        end

        test "everyone in the chat gets the new row" do
          assert_broadcasts(@tool.chat.to_gid_param, 1) do
            post tool_chat_message_reactions_path(@tool, @message), params: { emoji: "❤️" }
          end
        end

        test "someone outside the chat can't react" do
          outsider = User.create!(first_name: "Out", last_name: "Sider", email_address: "outsider@example.com", password: "password123")
          sign_in_as outsider

          post tool_chat_message_reactions_path(@tool, @message), params: { emoji: "👍" }

          assert_empty @message.reload.reactions
        end

        test "the API reacts and gets the message back with its reactions" do
          post tool_chat_message_reactions_path(@tool, @message), params: { emoji: "👀" }.to_json,
            headers: api_headers(@user).merge("Content-Type" => "application/json")

          assert_response :created
          reaction = response.parsed_body["reactions"].sole
          assert_equal "👀", reaction["emoji"]
          assert_equal 1, reaction["count"]
          assert_equal @user.email_address, reaction["users"].sole["email_address"]

          delete tool_chat_message_reaction_path(@tool, @message, "👀"), headers: api_headers(@user)
          assert_response :success
          assert_equal [], response.parsed_body["reactions"]
        end

        test "a message going takes its reactions with it" do
          @message.reactions.create!(user: @user, emoji: "👍")

          assert_difference -> { ::Chats::Reaction.count }, -1 do
            @message.destroy
          end
        end
      end
    end
  end
end
