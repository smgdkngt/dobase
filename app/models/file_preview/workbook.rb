# frozen_string_literal: true

require "roo"

class FilePreview
  # An .xlsx as sheets of text: what each cell holds, a formula's last result, dates as
  # dates. No formatting, charts or pictures. Reading runs nothing: a macro in the file
  # is never looked at.
  module Workbook
    MAX_SHEETS = 20

    def self.read(path)
      return unless Zip::File.open(path) { |zip| FilePreview.unpacks_small?(zip) }

      book = Roo::Excelx.new(path, file_warning: :ignore, disable_html_wrapper: true)
      book.sheets.first(MAX_SHEETS).map do |name|
        rows = []
        book.sheet_for(name).each_row(max_rows: MAX_ROWS, pad_cells: true) do |row|
          rows << row.map { |cell| text(cell&.value) }
        end
        Sheet.from(name, rows)
      end
    rescue StandardError
      # Not a workbook after all, or one that is broken in any of the ways a file someone
      # sent can be: nothing to show
      nil
    ensure
      book&.close
    end

    def self.text(value)
      case value
      when nil then ""
      when DateTime, Time then value.strftime("%Y-%m-%d %H:%M")
      when Date then value.iso8601
      when Float then value == value.to_i ? value.to_i.to_s : value.round(10).to_s
      else value.to_s
      end
    end
  end
end
