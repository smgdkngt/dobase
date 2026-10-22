# frozen_string_literal: true

module Mcp
  # One call of an MCP tool, refused ones too: who, through which connection,
  # what was asked (capped), how it went and how long it took. Kept thirty days.
  class ToolCall < ApplicationRecord
    self.table_name = "mcp_tool_calls"

    OUTCOMES = %w[ok error denied].freeze
    MAX_ARGUMENT_BYTES = 2.kilobytes
    KEPT = 30.days

    belongs_to :user
    belongs_to :access_token, optional: true

    validates :outcome, inclusion: { in: OUTCOMES }

    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    # What was asked, never whatever a client chose to send along
    def self.loggable(arguments)
      return {} unless arguments.is_a?(Hash)

      json = arguments.to_json
      json.bytesize > MAX_ARGUMENT_BYTES ? { "truncated" => json.truncate_bytes(MAX_ARGUMENT_BYTES) } : arguments
    end
  end
end
