# frozen_string_literal: true

class FilePreview
  # One sheet of a table as a page shows it: its cells as text, no more than MAX_ROWS by
  # MAX_COLUMNS of them, and whether the file had more.
  Sheet = Data.define(:name, :rows, :more) do
    # From rows of anything, of which one more than MAX_ROWS says there are more
    def self.from(name, rows)
      more = rows.size > MAX_ROWS || rows.any? { |row| row.size > MAX_COLUMNS }
      cells = rows.first(MAX_ROWS).map do |row|
        row.first(MAX_COLUMNS).map { |value| value.to_s.truncate(MAX_CELL_LENGTH) }
      end

      new(name: name, rows: cells, more: more)
    end

    def columns
      rows.map(&:size).max.to_i
    end
  end
end
