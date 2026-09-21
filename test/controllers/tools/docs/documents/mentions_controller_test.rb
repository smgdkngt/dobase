# frozen_string_literal: true

require "test_helper"

module Tools
  module Docs
    module Documents
      class MentionsControllerTest < ActionDispatch::IntegrationTest
        setup do
          @tool = tools(:shared_docs)
          @document = docs_documents(:shared_notes)
          sign_in_as users(:one)
        end

        test "picking a colleague tells them, naming whoever picked them" do
          assert_difference -> { users(:two).notifications.count }, 1 do
            post tool_docs_document_mentions_path(@tool, @document), params: { user_id: users(:two).id }, as: :json
          end

          assert_response :no_content
          notification = users(:two).notifications.last
          assert_equal "User One mentioned you in Shared Notes", notification.message
          assert_equal tool_docs_document_path(@tool, @document), notification.url
        end

        test "someone who isn't on the tool isn't told" do
          outsider = User.create!(first_name: "Out", last_name: "Sider", email_address: "outsider-mention@example.com", password: "password123")

          assert_no_difference -> { Noticed::Notification.count } do
            post tool_docs_document_mentions_path(@tool, @document), params: { user_id: outsider.id }, as: :json
          end
          assert_response :no_content
        end

        test "mentioning yourself tells nobody" do
          assert_no_difference -> { Noticed::Notification.count } do
            post tool_docs_document_mentions_path(@tool, @document), params: { user_id: users(:one).id }, as: :json
          end
        end

        test "a document from another tool is not found" do
          post tool_docs_document_mentions_path(@tool, docs_documents(:meeting_notes)), params: { user_id: users(:two).id }, as: :json

          assert_response :not_found
        end
      end
    end
  end
end
