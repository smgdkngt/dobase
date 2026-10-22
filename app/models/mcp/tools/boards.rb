# frozen_string_literal: true

module Mcp
  module Tools
    module Boards
      extend Declaring

      COLORS = %w[red orange yellow green blue purple none].freeze

      def self.card_params
        {
          description: text("The description, plain text (or HTML with html: true)"),
          html: html_flag,
          due: due,
          assignee: assignee,
          color: choice(COLORS, "Its colour, or none")
        }
      end

      # What a card's tool call says about the card, as the API takes it
      def self.card_attributes(call)
        call.instance_exec do
          attributes = {}
          attributes[:description] = rich(:description) if given?(:description)
          attributes[:due_date] = day(:due) if given?(:due)
          attributes[:assigned_user_id] = person(arg(:tool_id), arg(:assignee)) if given?(:assignee)
          attributes[:color] = arg(:color) == "none" ? "" : arg(:color) if given?(:color)
          attributes
        end
      end

      def self.card_path(call, suffix = nil)
        "/tools/#{call.arg(:tool_id)}/board/cards/#{call.arg(:card_id)}#{suffix}"
      end

      def self.card
        { tool_id: tool_id("boards"), card_id: id("The card's id", required: true) }
      end

      tool "card_list", "Show a board", "A board's columns in order, each with its cards.",
        params: { tool_id: tool_id("boards"), archived: flag("The archived cards instead of the active ones") },
        read_only: true do
        get "/tools/#{arg(:tool_id)}/board", archived: arg(:archived) ? "true" : nil
      end

      tool "card_show", "Show a card", "A card with its description, column, assignee, due date, comments and attachments.",
        params: card, read_only: true do
        get Boards.card_path(self)
      end

      tool "card_create", "Add a card", "Adds a card to the bottom of a column (the first column unless column is given).",
        params: { tool_id: tool_id("boards"), title: text("The card's title", required: true),
                  column: text("The column's id or name") }.merge(card_params) do
        columns = get("/tools/#{arg(:tool_id)}/board")["columns"]
        raise Tool::Error, "This board has no columns" if columns.empty?

        column = arg(:column) ? named(columns, arg(:column), "name", "column") : columns.first
        post "/columns/#{column["id"]}/cards", card: Boards.card_attributes(self).merge(title: arg(:title))
      end

      tool "card_update", "Change a card", "Changes a card's title, description, due date, assignee or colour.",
        params: card.merge(title: text("A new title")).merge(card_params) do
        attributes = Boards.card_attributes(self)
        attributes[:title] = arg(:title) if given?(:title)
        raise Tool::Error, "Nothing to change" if attributes.empty?

        patch Boards.card_path(self), card: attributes
      end

      tool "card_move", "Move a card", "Moves a card to another column, or to a position within its column.",
        params: card.merge(column: text("The column's id or name"), position: number("Its place in the column, 1 = top")) do
        raise Tool::Error, "Give a column, a position, or both" unless arg(:column) || arg(:position)

        body = {}
        if arg(:column)
          body[:column_id] = named(get("/tools/#{arg(:tool_id)}/board")["columns"], arg(:column), "name", "column")["id"]
        end
        body[:position] = arg(:position) - 1 if arg(:position)
        patch Boards.card_path(self, "/position"), body
      end

      tool "card_archive", "Archive a card", "Archives a card; card_unarchive brings it back.", params: card do
        post Boards.card_path(self, "/archive")
      end

      tool "card_unarchive", "Bring a card back", "Brings an archived card back to its column.", params: card do
        delete Boards.card_path(self, "/archive")
      end

      tool "card_delete", "Delete a card", "Deletes a card for good, with its comments and attachments. card_archive can be undone.",
        params: card, destructive: true do
        delete Boards.card_path(self)
      end

      tool "card_comment", "Comment on a card", "Adds a comment to a card.",
        params: card.merge(text: text("The comment, plain text (or HTML with html: true)", required: true), html: html_flag) do
        post Boards.card_path(self, "/comments"), body: rich(:text)
      end

      tool "card_uncomment", "Delete a comment from a card", "Deletes a comment: your own, or anyone's on a board you own.",
        params: card.merge(comment_id: id("The comment's id", required: true)), destructive: true do
        delete Boards.card_path(self, "/comments/#{arg(:comment_id)}")
      end

      tool "card_attach", "Attach files to a card", "Attaches files to a card, 25 MB each at most.",
        params: card.merge(files: file_list("The files", required: true)) do
        files(:files).map { upload Boards.card_path(self, "/attachments"), file: it }
      end

      tool "column_create", "Add a column", "Adds a column to the end of a board.",
        params: { tool_id: tool_id("boards"), name: text("Its name", required: true) } do
        post "/tools/#{arg(:tool_id)}/board/columns", name: arg(:name)
      end

      tool "column_rename", "Rename a column", "Renames a column.",
        params: { tool_id: tool_id("boards"), column_id: id("The column's id", required: true), name: text("Its new name", required: true) } do
        patch "/tools/#{arg(:tool_id)}/board/columns/#{arg(:column_id)}", name: arg(:name)
      end

      tool "column_delete", "Delete a column", "Deletes a column and every card in it, for good.",
        params: { tool_id: tool_id("boards"), column_id: id("The column's id", required: true) }, destructive: true do
        delete "/tools/#{arg(:tool_id)}/board/columns/#{arg(:column_id)}"
      end
    end
  end
end
