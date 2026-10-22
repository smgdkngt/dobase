# frozen_string_literal: true

module Mcp
  module Tools
    module Boards
      extend Declaring

      tool "card_list", "Show a board", "A board's columns in order, each with its cards.",
        params: { tool_id: tool_id("boards"), archived: flag("The archived cards instead of the active ones") },
        read_only: true do
        get "/tools/#{arg(:tool_id)}/board", archived: arg(:archived) ? "true" : nil
      end

      tool "card_show", "Show a card", "A card with its description, column, assignee, due date, comments and attachments.",
        params: { tool_id: tool_id("boards"), card_id: id("The card's id", required: true) }, read_only: true do
        get "/tools/#{arg(:tool_id)}/board/cards/#{arg(:card_id)}"
      end
    end
  end
end
