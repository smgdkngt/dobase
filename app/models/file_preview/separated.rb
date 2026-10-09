# frozen_string_literal: true

require "csv"

class FilePreview
  # A csv or tsv file as one sheet. Commas, semicolons (what a Dutch Excel writes) or
  # tabs: whichever the first line has most of.
  module Separated
    SEPARATORS = [ ",", ";", "\t" ].freeze
    UTF_16_MARKS = [ "\xFF\xFE".b, "\xFE\xFF".b ].freeze

    # `cut` when the bytes are only the start of the file: its last line is then left out
    def self.read(bytes, tabs: false, cut: false)
      text = text_of(bytes, cut)
      # Not what a field has in quotes: "Lee, Ann";12 is split on the semicolon
      first_line = text.each_line.first.to_s.gsub(/"[^"]*"/, "")
      separator = tabs ? "\t" : SEPARATORS.max_by { |candidate| first_line.count(candidate) }

      rows = []
      begin
        CSV.parse(text, col_sep: separator, liberal_parsing: true) do |row|
          rows << row
          break if rows.size > MAX_ROWS
        end
      rescue CSV::MalformedCSVError
        # The cut can fall inside a field in quotes: the rows before it are whole
        return unless cut
      end
      rows.any? ? [ Sheet.from(nil, rows, more: cut) ] : nil
    rescue EncodingError
      nil
    end

    # UTF-8, what Excel calls "Unicode text" (UTF-16), or else what Windows wrote
    def self.text_of(bytes, cut)
      bytes = bytes.b
      if bytes.start_with?(*UTF_16_MARKS)
        text = bytes.force_encoding(Encoding::UTF_16).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        cut ? whole_lines(text) : text
      else
        # A line ends on the same byte in both, and the cut can fall inside a character
        bytes = whole_lines(bytes) if cut
        text = bytes.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
        text.valid_encoding? ? text : text.encode(Encoding::UTF_8, Encoding::WINDOWS_1252)
      end
    end

    def self.whole_lines(text)
      last = text.rindex("\n".encode(text.encoding))
      last ? text[0..last] : text
    end
  end
end
