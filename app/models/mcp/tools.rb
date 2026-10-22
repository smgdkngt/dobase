# frozen_string_literal: true

module Mcp
  # Every MCP tool, one per thing the dobase CLI can do, named like its command
  # (`dobase card show` is `card_show`). They are declared per kind of tool in
  # `Mcp::Tools::*`, each with `tool`.
  module Tools
    KINDS = %w[Workspace Boards Todos Docs Chat Mail Calendar Files].freeze

    def self.all
      @all ||= KINDS.flat_map { |kind| const_get(kind).tools }.index_by(&:name)
    end

    def self.find(name)
      all[name.to_s]
    end

    # Declaring tools, and the shapes of what they take
    module Declaring
      def tools
        @tools ||= []
      end

      def tool(name, title, description, **options, &handler)
        tools << Tool.new(name, title:, description:, **options, &handler)
      end

      def id(description, required: false)
        { type: "integer", minimum: 1, description:, required: }
      end

      def text(description, required: false)
        { type: "string", description:, required: }
      end

      def flag(description)
        { type: "boolean", description: }
      end

      def number(description, minimum: 1, maximum: nil)
        { type: "integer", minimum:, maximum:, description: }.compact
      end

      def date(description, required: false)
        { type: "string", pattern: '^\d{4}-\d{2}-\d{2}$', description: "#{description} (YYYY-MM-DD)", required: }
      end

      def choice(values, description, required: false)
        { type: "string", enum: values, description:, required: }
      end

      def list(item, description, required: false)
        { type: "array", items: item, description:, required: }
      end

      def tool_id(kind)
        id("The #{kind} tool's id (from tool_list)", required: true)
      end
    end
  end
end
