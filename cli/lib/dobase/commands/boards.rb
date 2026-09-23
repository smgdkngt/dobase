# frozen_string_literal: true

module Dobase
  module Commands
    class Boards < Command
      COLORS = %w[red orange yellow green blue purple].freeze
      CARD_FLAGS = {
        description: [ "TEXT", "Description (plain text, or HTML with --html)" ],
        html: [ nil, "The description is HTML" ],
        due: [ "DATE", "Due date: YYYY-MM-DD, today, tomorrow or none" ],
        assignee: [ "USER", "me, none, a user id, email or name" ],
        color: [ "COLOR", "#{COLORS.join(", ")} or none" ]
      }.freeze

      noun "card", "Cards on a board (boards tools)"
      noun "column", "Columns on a board (boards tools)"

      command "card list", "Show a board: its columns and their cards", args: %w[TOOL],
        flags: { archived: [ nil, "Show archived cards instead of active ones" ] } do |ref, archived: false|
        board_tool = tool(ref, "boards")
        board = get("/tools/#{board_tool["id"]}/board", archived: archived || nil)

        output(board) do
          say "#{board_tool["name"]} (board #{board_tool["id"]}) #{board["url"]}"
          board["columns"].each do |column|
            say
            say "#{column["name"]} [column #{column["id"]}]"
            say "  (no #{"archived " if archived}cards)" if column["cards"].empty?
            table(column["cards"].map { |card| [ "#{board_tool["id"]}/#{card["id"]}", card["title"], card_summary(card) ] })
          end
        end
      end

      command "card show", "Show a card with its description, comments and attachments", args: %w[TOOL/CARD] do |ref|
        board_tool, id = tool_and_id(ref, "boards", "card")
        card = get("/tools/#{board_tool["id"]}/board/cards/#{id}")

        output(card) do
          say "#{card["title"]} (card #{board_tool["id"]}/#{card["id"]})"
          field "Board", "#{board_tool["name"]} › #{card.dig("column", "name")}"
          field "Assignee", person(card["assignee"])
          field "Due", card["due_date"]
          field "Color", card["color"]
          field "Archived", "yes" if card["archived"]
          field "Created", [ moment(card["created_at"]), card.dig("creator", "name") ].compact.join(" by ")
          field "URL", card["url"]

          unless card["description"].strip.empty?
            say
            say "Description:"
            paragraph card["description"]
          end

          say
          say "Comments (#{card["comments"].size}):"
          card["comments"].each do |comment|
            say "  #{comment.dig("user", "name") || "Former member"} · #{moment(comment["created_at"])} [comment #{comment["id"]}]"
            paragraph comment["body"], indent: 4
          end

          unless card["attachments"].empty?
            say
            say "Attachments (#{card["attachments"].size}):"
            table(card["attachments"].map { |attachment| [ attachment["filename"], bytes(attachment["file_size"]), attachment["download_url"] ] })
          end
        end
      end

      command "card create", "Add a card to a board (to the first column unless --column)", args: %w[TOOL TITLE],
        flags: CARD_FLAGS.merge(column: [ "COLUMN", "Column id or name" ]) do |ref, title, column: nil, **options|
        board_tool = tool(ref, "boards")
        target = find_column(board_tool, column)

        card = post("/columns/#{target["id"]}/cards", card: card_attributes(board_tool, options).merge(title: title))
        output(card) { say "Created card #{board_tool["id"]}/#{card["id"]} #{quoted(card["title"])} in #{target["name"]}: #{card["url"]}" }
      end

      command "card update", "Change a card's title, description, due date, assignee or color", args: %w[TOOL/CARD],
        flags: CARD_FLAGS.merge(title: [ "TEXT", "New title" ]) do |ref, title: nil, **options|
        board_tool, id = tool_and_id(ref, "boards", "card")
        attributes = card_attributes(board_tool, options)
        attributes[:title] = title if title
        raise UsageError, "Nothing to update. See `dobase help card`." if attributes.empty?

        card = patch("/tools/#{board_tool["id"]}/board/cards/#{id}", card: attributes)
        output(card) { say "Updated card #{board_tool["id"]}/#{card["id"]} #{quoted(card["title"])}." }
      end

      command "card move", "Move a card to another column, or to a position within its column", args: %w[TOOL/CARD [COLUMN]],
        flags: { position: [ "N", "Position in the column, 1 = top (default: bottom)" ] } do |ref, column = nil, position: nil|
        board_tool, id = tool_and_id(ref, "boards", "card")
        raise UsageError, "Give a COLUMN, a --position, or both." if column.nil? && position.nil?

        target = find_column(board_tool, column) if column
        body = { column_id: target&.dig("id"), position: position && [ position.to_i - 1, 0 ].max }.compact
        card = patch("/tools/#{board_tool["id"]}/board/cards/#{id}/position", body)
        output(card) { say "Moved card #{board_tool["id"]}/#{card["id"]} #{quoted(card["title"])} to #{card.dig("column", "name")}, position #{card["position"] + 1}." }
      end

      command "card archive", "Archive a card (reversible with card unarchive)", args: %w[TOOL/CARD] do |ref|
        board_tool, id = tool_and_id(ref, "boards", "card")
        card = post("/tools/#{board_tool["id"]}/board/cards/#{id}/archive")
        output(card) { say "Archived card #{board_tool["id"]}/#{card["id"]} #{quoted(card["title"])}." }
      end

      command "card unarchive", "Bring an archived card back", args: %w[TOOL/CARD] do |ref|
        board_tool, id = tool_and_id(ref, "boards", "card")
        card = delete("/tools/#{board_tool["id"]}/board/cards/#{id}/archive")
        output(card) { say "Unarchived card #{board_tool["id"]}/#{card["id"]} #{quoted(card["title"])}." }
      end

      command "card delete", "Delete a card permanently, with its comments and attachments", args: %w[TOOL/CARD] do |ref|
        board_tool, id = tool_and_id(ref, "boards", "card")
        delete("/tools/#{board_tool["id"]}/board/cards/#{id}")
        output(nil) { say "Deleted card #{board_tool["id"]}/#{id}." }
      end

      command "card comment", "Comment on a card", args: %w[TOOL/CARD TEXT],
        flags: { html: [ nil, "TEXT is HTML" ] } do |ref, body, html: false|
        board_tool, id = tool_and_id(ref, "boards", "card")
        comment = post("/tools/#{board_tool["id"]}/board/cards/#{id}/comments", body: rich_text(body, html: html))
        output(comment) { say "Commented on card #{board_tool["id"]}/#{id} [comment #{comment["id"]}]." }
      end

      command "card attach", "Attach files to a card (25 MB max each)", args: %w[TOOL/CARD PATH...] do |ref, *paths|
        board_tool, id = tool_and_id(ref, "boards", "card")
        missing = paths.reject { |path| File.file?(path) }
        raise UsageError, "No such file: #{missing.join(", ")}" if missing.any?

        attachments = paths.map { |path| client.upload("/tools/#{board_tool["id"]}/board/cards/#{id}/attachments", files: { file: path }) }
        output(attachments) { attachments.each { |attachment| say "Attached #{attachment["filename"]} (#{bytes(attachment["file_size"])}) to card #{board_tool["id"]}/#{id}." } }
      end

      command "column create", "Add a column to the end of a board", args: %w[TOOL NAME] do |ref, name|
        board_tool = tool(ref, "boards")
        column = post("/tools/#{board_tool["id"]}/board/columns", name: name)
        output(column) { say "Created column #{board_tool["id"]}/#{column["id"]} #{quoted(column["name"])}." }
      end

      command "column rename", "Rename a column", args: %w[TOOL/COLUMN NAME] do |ref, name|
        board_tool, id = tool_and_id(ref, "boards", "column")
        column = patch("/tools/#{board_tool["id"]}/board/columns/#{id}", name: name)
        output(column) { say "Renamed column #{board_tool["id"]}/#{column["id"]} to #{quoted(column["name"])}." }
      end

      command "column delete", "Delete a column and every card in it", args: %w[TOOL/COLUMN] do |ref|
        board_tool, id = tool_and_id(ref, "boards", "column")
        delete("/tools/#{board_tool["id"]}/board/columns/#{id}")
        output(nil) { say "Deleted column #{board_tool["id"]}/#{id}." }
      end

      private

      def card_summary(card)
        [
          ("due #{card["due_date"]}" if card["due_date"]),
          ("@#{card.dig("assignee", "name")}" if card["assignee"]),
          card["color"].to_s.empty? ? nil : card["color"],
          (count(card["comments_count"], "comment") if card["comments_count"].positive?),
          (count(card["attachments_count"], "file") if card["attachments_count"].positive?)
        ].compact.join("  ")
      end

      def find_column(board_tool, ref)
        columns = get("/tools/#{board_tool["id"]}/board")["columns"]
        return columns.first || raise(Error, "#{board_tool["name"]} has no columns.") if ref.nil?

        match = columns.find { |column| column["id"].to_s == ref } ||
          columns.find { |column| column["name"].casecmp?(ref) } ||
          columns.find { |column| column["name"].downcase.start_with?(ref.downcase) }
        match || raise(Error, "No column matches #{quoted(ref)}. Columns: #{columns.map { |column| column["name"] }.join(", ")}")
      end

      def card_attributes(board_tool, options)
        attributes = {}
        attributes[:description] = rich_text(options[:description], html: options[:html]) if options[:description]
        attributes[:due_date] = date_param(options[:due]) if options[:due]
        attributes[:assigned_user_id] = user_id(board_tool, options[:assignee]) if options[:assignee]
        if options[:color]
          raise UsageError, "--color must be one of: #{COLORS.join(", ")}, none" unless (COLORS + [ "none" ]).include?(options[:color])
          attributes[:color] = options[:color] == "none" ? "" : options[:color]
        end
        attributes
      end
    end
  end
end
