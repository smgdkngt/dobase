# frozen_string_literal: true

module Mcp
  # One thing a client can ask through MCP: a name, what it takes, and what it
  # does with the JSON API. The same tool serves Claude and the dobase CLI, so
  # what it gives back is the API's own JSON, unchanged.
  #
  # A tool that only reads says `read_only: true`. One that destroys or reaches
  # outside Dobase (deleting, sending mail) says `destructive: true`: Claude
  # asks before it calls one, and the tool does nothing until it is called
  # with `confirm: true` as well.
  class Tool
    attr_reader :name, :title, :description, :properties, :required, :handler

    def initialize(name, title:, description:, params: {}, read_only: false, destructive: false, &handler)
      @name = name
      @title = title
      @read_only = read_only
      @destructive = destructive
      @handler = handler

      params = params.merge(confirm: { type: "boolean", description: "true once the user has said yes to this", required: true }) if destructive
      @required = params.select { |_, schema| schema[:required] }.keys.map(&:to_s)
      @properties = params.transform_values { |schema| schema.except(:required) }.transform_keys(&:to_s)
      @description = destructive ? "#{description} Ask the user first, then call with confirm: true." : description
    end

    def read_only? = @read_only
    def destructive? = @destructive

    def input_schema
      { type: "object", properties:, required:, additionalProperties: false }.compact_blank.merge(type: "object")
    end

    def annotations
      { title:, read_only_hint: read_only?, destructive_hint: destructive?, idempotent_hint: read_only?, open_world_hint: false }
    end

    def call(api, arguments)
      Call.new(self, api, arguments).run
    end

    # What a tool's block runs in: the API, the arguments, and a few helpers
    class Call
      attr_reader :api

      def initialize(tool, api, arguments)
        @tool = tool
        @api = api
        @arguments = arguments.to_h.transform_keys(&:to_s)
      end

      def run
        if @tool.destructive? && arg(:confirm) != true
          raise Error, "Nothing done. Ask the user whether this may happen, then call #{@tool.name} again with confirm: true."
        end

        instance_exec(&@tool.handler)
      end

      def arg(name)
        value = @arguments[name.to_s]
        value.is_a?(String) ? value.strip.presence : value
      end

      def args(*names)
        names.index_with { |name| arg(name) }.compact
      end

      def get(...) = api.get(...)
      def post(...) = api.post(...)
      def patch(...) = api.patch(...)
      def delete(...) = api.delete(...)
    end

    # What went wrong in words the client can act on
    class Error < StandardError; end
  end
end
