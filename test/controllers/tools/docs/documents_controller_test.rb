# frozen_string_literal: true

require "test_helper"

module Tools
  module Docs
    class DocumentsControllerTest < ActionDispatch::IntegrationTest
      setup do
        sign_in_as users(:one)
        @tool = tools(:my_docs)
      end

      test "create creates new document and redirects to edit" do
        assert_difference "::Docs::Document.count", 1 do
          post tool_docs_documents_path(@tool)
        end

        document = ::Docs::Document.last
        assert_redirected_to edit_tool_docs_document_path(@tool, document)
        assert_equal "Untitled", document.title
        assert_equal @tool, document.tool
      end

      test "requires authentication" do
        sign_out

        assert_no_difference "::Docs::Document.count" do
          post tool_docs_documents_path(@tool)
        end

        assert_redirected_to new_session_path
      end
    end
  end
end
