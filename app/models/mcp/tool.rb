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

    def initialize(name, title:, description:, params: {}, read_only: false, destructive: false, open_world: false, &handler)
      @name = name
      @title = title
      @read_only = read_only
      @destructive = destructive
      @open_world = open_world
      @handler = handler

      # Not required: without it the tool itself says to ask first, which a refused schema would not
      params = params.merge(confirm: { type: "boolean", description: "true once the user has said yes to this" }) if destructive
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
      { title:, read_only_hint: read_only?, destructive_hint: destructive?, idempotent_hint: read_only?, open_world_hint: @open_world }
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
        @arguments = arguments.to_h.deep_stringify_keys
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

      def given?(name)
        @arguments.key?(name.to_s)
      end

      # The arguments that were given, as they were: an empty one clears what it names
      def given_args(*names)
        names.select { given?(it) }.index_with { @arguments[it.to_s] }
      end

      def get(...) = api.get(...)
      def post(...) = api.post(...)
      def patch(...) = api.patch(...)
      def delete(...) = api.delete(...)
      def upload(...) = api.upload(...)

      # A text argument as rich text: HTML as it is with html: true, else plain text in paragraphs
      def rich(name)
        value = @arguments[name.to_s].to_s
        arg(:html) ? value : Text.paragraphs(value)
      end

      # A date argument as the API takes it: YYYY-MM-DD, today, tomorrow, or none to clear it
      def day(name)
        case value = arg(name)
        when nil, "none" then nil
        when "today" then Time.zone.today.iso8601
        when "tomorrow" then Time.zone.tomorrow.iso8601
        else Date.iso8601(value).iso8601
        end
      rescue Date::Error
        raise Error, "#{name} must be a date like 2026-10-01, today, tomorrow or none"
      end

      # Someone a tool is shared with, by me, none, an id, an address or part of a name
      def person(tool_id, value)
        case value.to_s
        when "none" then return nil
        when "me" then return get("/profile")["id"]
        when /\A\d+\z/ then return value.to_i
        end

        people = get("/tools/#{tool_id}")["collaborators"].to_a
        matches = people.select { it["email_address"].to_s.casecmp?(value) }
        matches = people.select { it["name"].to_s.downcase.include?(value.downcase) } if matches.empty?
        case matches.size
        when 0 then raise Error, "Nobody this tool is shared with matches #{value.inspect}"
        when 1 then matches.first["id"]
        else raise Error, "#{value.inspect} matches #{matches.pluck("name").to_sentence}: give an address or id"
        end
      end

      # A column, list or calendar by its id or its name
      def named(items, reference, key, kind)
        found = items.find { it["id"].to_s == reference.to_s } ||
          items.select { it[key].to_s.casecmp?(reference.to_s) }.then { it.one? ? it.first : nil }
        found || raise(Error, "No #{kind} #{reference.inspect}; there are: #{items.pluck(key).to_sentence}")
      end

      # Files given as name and base64 content
      def files(name)
        Array(@arguments[name.to_s]).map do |file|
          content = Base64.strict_decode64(file["content_base64"].to_s)
          Rack::Multipart::UploadedFile.new(io: StringIO.new(content), filename: File.basename(file["name"].to_s),
            content_type: file["content_type"].presence || Marcel::MimeType.for(name: file["name"].to_s))
        rescue ArgumentError
          raise Error, "#{file["name"]} isn't base64"
        end
      end
    end

    # What went wrong in words the client can act on
    class Error < StandardError; end
  end
end
