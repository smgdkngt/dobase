# frozen_string_literal: true

module Mcp
  module Tools
    module Docs
      extend Declaring

      def self.document
        { tool_id: tool_id("docs"), document_id: id("The document's id", required: true) }
      end

      def self.path(call)
        "/tools/#{call.arg(:tool_id)}/docs/documents/#{call.arg(:document_id)}"
      end

      tool "doc_list", "List documents", "A docs tool's documents, last edited first, with the start of each.",
        params: { tool_id: tool_id("docs") }, read_only: true do
        get "/tools/#{arg(:tool_id)}/docs"
      end

      tool "doc_show", "Show a document", "A document's title and whole content, as plain text and as HTML.",
        params: document, read_only: true do
        get Docs.path(self)
      end

      tool "doc_create", "Write a document", "Adds a document to a docs tool.",
        params: { tool_id: tool_id("docs"), title: text("Its title (Untitled without one)"),
                  content: text("Its content, plain text (or HTML with html: true)"), html: html_flag } do
        attributes = { title: arg(:title) }.compact
        attributes[:content] = rich(:content) if given?(:content)
        post "/tools/#{arg(:tool_id)}/docs/documents", docs_document: attributes
      end

      tool "doc_update", "Change a document",
        "Changes a document's title or replaces its whole content: to change a part, read content_html with doc_show, " \
        "change that and send all of it with html: true. Refused while someone has the document open in the editor.",
        params: document.merge(title: text("A new title"), content: text("The whole new content"), html: html_flag) do
        attributes = { title: arg(:title) }.compact
        attributes[:content] = rich(:content) if given?(:content)
        raise Tool::Error, "Nothing to change" if attributes.empty?

        patch Docs.path(self), docs_document: attributes
      end

      tool "doc_delete", "Delete a document", "Deletes a document for good.", params: document, destructive: true do
        delete Docs.path(self)
      end
    end
  end
end
