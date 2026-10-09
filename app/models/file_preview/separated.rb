# frozen_string_literal: true

require "csv"

class FilePreview
  # A csv or tsv file as one sheet. Commas, semicolons (what a Dutch Excel writes) or
  # tabs: whichever the first line has most of.
  module Separated
    SEPARATORS = [ ",", ";", "\t" ].freeze

    def self.read(text, tabs: false)
      text = text.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
      text = text.encode(Encoding::UTF_8, Encoding::WINDOWS_1252) unless text.valid_encoding?

      first_line = text.each_line.first.to_s
      separator = tabs ? "\t" : SEPARATORS.max_by { |candidate| first_line.count(candidate) }

      rows = []
      CSV.parse(text, col_sep: separator, liberal_parsing: true) do |row|
        rows << row
        break if rows.size > MAX_ROWS
      end
      rows.any? ? [ Sheet.from(nil, rows) ] : nil
    rescue CSV::MalformedCSVError, EncodingError
      nil
    end
  end
end
