# frozen_string_literal: true

module Dobase
  module Commands
    class Search < Command
      noun "search", "Search every tool you share"

      command "search", "Find cards, todos, documents, files, messages, events and mail that match", args: %w[QUERY...] do |*words|
        query = words.join(" ").strip
        raise UsageError, "Give at least two characters to search for." if query.length < 2

        result = get("/search", q: query)

        output(result) do
          results = result["results"]
          say("Nothing matches \"#{query}\".") if results.empty?
          table(results.map { |hit| [ hit["kind"], hit["title"], hit["tool_name"], hit["url"] ] }, indent: 0)
        end
      end
    end
  end
end
