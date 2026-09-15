# frozen_string_literal: true

module Dobase
  module Commands
    class Docs < Command
      CONTENT_FLAGS = {
        content: [ "TEXT", "Content (plain text, or HTML with --html)" ],
        html: [ nil, "The content is HTML" ]
      }.freeze

      noun "doc", "Documents (docs tools)"

      command "doc list", "List the documents in a docs tool, last edited first", args: %w[TOOL] do |ref|
        docs_tool = tool(ref, "docs")
        docs = get("/tools/#{docs_tool["id"]}/docs")

        output(docs) do
          say "#{docs_tool["name"]} (docs #{docs_tool["id"]}) #{docs["url"]}"
          say
          say "  (no documents)" if docs["documents"].empty?
          table(docs["documents"].map { |document| [ "#{docs_tool["id"]}/#{document["id"]}", document["title"], document_summary(document) ] })
        end
      end

      command "doc show", "Show a document with its content", args: %w[TOOL/DOC],
        flags: { html: [ nil, "Print the content as HTML instead of plain text" ] } do |ref, html: false|
        docs_tool, id = tool_and_id(ref, "docs", "doc")
        document = get("/tools/#{docs_tool["id"]}/docs/documents/#{id}")

        output(document) do
          say "#{document["title"]} (doc #{docs_tool["id"]}/#{document["id"]})"
          field "Docs", docs_tool["name"]
          field "Editing", ("#{document.dig("locked_by", "name")} has it open in the editor" if document["locked"])
          field "Created", [ moment(document["created_at"]), document.dig("creator", "name") ].compact.join(" by ")
          field "Updated", [ moment(document["updated_at"]), document.dig("updated_by", "name") ].compact.join(" by ")
          field "URL", document["url"]
          say

          content = html ? document["content_html"] : document["content"]
          say content.strip.empty? ? "(empty)" : content
        end
      end

      command "doc create", "Create a document", args: %w[TOOL TITLE], flags: CONTENT_FLAGS do |ref, title, content: nil, html: false|
        docs_tool = tool(ref, "docs")
        attributes = { title: title }
        attributes[:content] = rich_text(content, html: html) if content

        document = post("/tools/#{docs_tool["id"]}/docs/documents", docs_document: attributes)
        output(document) { say "Created doc #{docs_tool["id"]}/#{document["id"]} #{quoted(document["title"])}: #{document["url"]}" }
      end

      command "doc update", "Rename a document or replace its content (refused while someone else is editing it)",
        args: %w[TOOL/DOC], flags: { title: [ "TEXT", "New title" ] }.merge(CONTENT_FLAGS) do |ref, title: nil, content: nil, html: false|
        docs_tool, id = tool_and_id(ref, "docs", "doc")
        attributes = {}
        attributes[:title] = title if title
        attributes[:content] = rich_text(content, html: html) if content
        raise UsageError, "Nothing to update. See `dobase help doc`." if attributes.empty?

        document = patch("/tools/#{docs_tool["id"]}/docs/documents/#{id}", docs_document: attributes)
        output(document) { say "Updated doc #{docs_tool["id"]}/#{document["id"]} #{quoted(document["title"])}." }
      end

      command "doc delete", "Delete a document permanently", args: %w[TOOL/DOC] do |ref|
        docs_tool, id = tool_and_id(ref, "docs", "doc")
        delete("/tools/#{docs_tool["id"]}/docs/documents/#{id}")
        output(nil) { say "Deleted doc #{docs_tool["id"]}/#{id}." }
      end

      private

      def document_summary(document)
        [
          [ "edited #{moment(document["updated_at"])}", document.dig("updated_by", "name") ].compact.join(" by "),
          ("#{document.dig("locked_by", "name")} is editing" if document["locked"])
        ].compact.join("  ")
      end
    end
  end
end
