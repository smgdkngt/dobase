# frozen_string_literal: true

module Mcp
  module Tools
    module Docs
      extend Declaring

      tool "doc_list", "List documents", "A docs tool's documents, last edited first, with the start of each.",
        params: { tool_id: tool_id("docs") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/docs"
      end

      tool "doc_show", "Show a document", "A document's title and whole content, as plain text and as HTML.",
        params: { tool_id: tool_id("docs"), document_id: id("The document's id", required: true) }, read_only: true do
        get "/tools/#{arg(:tool_id)}/docs/documents/#{arg(:document_id)}"
      end
    end
  end
end
