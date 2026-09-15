# frozen_string_literal: true

require "dobase/client"
require "dobase/config"
require "dobase/command"
Dir[File.join(__dir__, "commands", "*.rb")].sort.each { |file| require file }

module Dobase
  VERSION = "1.0.0"

  class CLI
    INTRO = <<~TEXT
      dobase: work in your Dobase tools from the command line.

      Usage: dobase NOUN VERB [ARGS] [OPTIONS] [--json]

      TOOL is a tool id or (part of) its name. Things inside a tool are TOOL/ID,
      e.g. 12/104; list commands print these references. A TEXT value of "-" is
      read from stdin. --json prints the raw API response instead of text.
      `dobase help NOUN` shows the options of every command for that noun.
    TEXT

    def initialize(argv, out: $stdout, err: $stderr)
      # Arguments are text for the API; don't let a C/POSIX locale turn them into binary.
      @argv = argv.map { |arg| arg.dup.force_encoding(Encoding::UTF_8) }
      @out = out
      @err = err
    end

    def run
      json = !@argv.delete("--json").nil?

      if @argv.empty? || %w[help --help -h].include?(@argv.first)
        help(@argv[1])
        return 0
      end

      definition, rest = find(@argv)
      if definition.nil?
        help(@argv.first, unknown: true)
        return 2
      end

      command = definition.klass.new(config: Config.new, out: @out, json: json, user_agent: "dobase-cli/#{VERSION}")
      command.invoke(definition, rest)
      0
    rescue UsageError => error
      @err.puts error.message.gsub(Command::CONTROL_CHARACTERS, "")
      2
    rescue Error, SystemCallError => error
      @err.puts "Error: #{error.message.gsub(Command::CONTROL_CHARACTERS, "")}"
      1
    rescue Interrupt
      130
    end

    private

    def find(argv)
      if argv.size >= 2 && (definition = Command::DEFINITIONS["#{argv[0]} #{argv[1]}"])
        [ definition, argv.drop(2) ]
      elsif (definition = Command::DEFINITIONS[argv[0]])
        [ definition, argv.drop(1) ]
      end
    end

    def help(noun = nil, unknown: false)
      groups = Command::DEFINITIONS.values
        .group_by { |definition| definition.name.include?(" ") ? definition.name.split.first : nil }
        .sort_by { |group, _| [ group.nil? ? 0 : (group == "tool" ? 1 : 2), group.to_s ] }.to_h
      @err.puts "Unknown command: dobase #{@argv.join(" ")}\n\n" if unknown

      if noun && groups.key?(noun)
        @out.puts "#{noun}: #{Command::NOUNS[noun]}\n\n"
        groups[noun].each do |definition|
          @out.puts "  #{definition.usage}"
          @out.puts "      #{definition.summary}"
          definition.flags.each do |flag, (placeholder, description)|
            @out.puts "      --#{[ flag.to_s.tr("_", "-"), placeholder ].compact.join(" ").ljust(24)} #{description}"
          end
          @out.puts
        end
        return
      end

      @out.puts INTRO
      groups.each do |group, definitions|
        @out.puts
        @out.puts group ? "#{group}: #{Command::NOUNS[group]}" : "General"
        width = definitions.map { |definition| definition.usage.length }.max
        definitions.each { |definition| @out.puts "  #{definition.usage.ljust(width)}  #{definition.summary}" }
      end
    end
  end
end
