# frozen_string_literal: true

class FilePreview
  # One sheet of a table as a page shows it: its cells as text, no more than MAX_ROWS by
  # MAX_COLUMNS of them, every row as wide as the widest, and whether the file had more.
  Sheet = Data.define(:name, :rows, :more) do
    # From rows of anything. One row more than MAX_ROWS says there are more, as does `more`.
    def self.from(name, rows, more: false)
      more ||= rows.size > MAX_ROWS || rows.any? { |row| row.size > MAX_COLUMNS }
      width = [ rows.first(MAX_ROWS).map(&:size).max.to_i, MAX_COLUMNS ].min
      cells = rows.first(MAX_ROWS).map do |row|
        Array.new(width) { |column| row[column].to_s.truncate(MAX_CELL_LENGTH) }
      end

      new(name: name, rows: cells, more: more)
    end
  end
end
