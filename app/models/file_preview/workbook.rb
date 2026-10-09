# frozen_string_literal: true

class FilePreview
  # An .xlsx as sheets of text: what each cell holds, a formula's last result, dates as
  # dates and percentages as percentages. No other formatting, no charts or pictures, and
  # not the sheets the workbook hides. Reading runs nothing: a macro is never looked at.
  #
  # A sheet is read as it comes out of the zip (Package) and only as far as a page shows
  # it: MAX_ROWS rows, of which the cells in the first MAX_COLUMNS columns are kept. Where
  # a cell says it is (`r="ZZZ9"`) only decides whether it is kept, so no file can have a
  # row filled up to a column it names.
  module Workbook
    MAX_SHEETS = 20
    MAX_STYLES = 65_536
    MAX_LISTED = 1000

    BOOK = "xl/workbook.xml"
    RELATIONS = "xl/_rels/workbook.xml.rels"
    STYLES = "xl/styles.xml"
    STRINGS = "xl/sharedStrings.xml"

    # The number formats a workbook has without naming them, as far as they are no plain number
    BUILT_IN_FORMATS = {
      9 => :percent, 10 => :percent, 18 => :time, 19 => :time, 20 => :time, 21 => :time, 45 => :time, 46 => :duration, 47 => :time
    }.merge([ 14, 15, 16, 17, 22, *27..36, *50..58 ].index_with(:date)).freeze

    def self.read(path, budget = Package::Budget.new)
      Package.open(path, budget) do |package|
        book = package.read(BOOK, Book.new) or next
        parts = package.read(RELATIONS, Relations.new)&.parts || {}
        formats = package.read(STYLES, Styles.new)&.formats || []

        sheets = book.sheets.select { |sheet| parts[sheet.id] }.first(MAX_SHEETS).filter_map do |sheet|
          cells = package.read(parts[sheet.id], Cells.new(formats, book.date1904))
          [ sheet.name, cells ] if cells
        end
        next if sheets.empty?

        # A text is in the sheet as its number in the workbook's list of texts
        wanted = sheets.flat_map { |_, cells| cells.rows.flatten.grep(Integer) }.to_set
        strings = (package.read(STRINGS, Strings.new(wanted))&.strings if wanted.any?) || {}

        sheets.map do |name, cells|
          rows = cells.rows.map { |row| row.map { |cell| cell.is_a?(Integer) ? strings[cell] : cell } }
          Sheet.from(name, rows, more: cells.more)
        end
      end
    end

    # What a format's code makes of a number: a :date, a :time of day, a :duration, a
    # :percent, or nothing but the number
    def self.kind_of_format(code)
      # Without what is only written out ("kg", \k), a colour or a currency ([Red], [$-413]).
      # [h] stays: hours that count on past 24.
      bare = code.to_s.first(255).gsub(/"[^"]*"|\\.|\[(?![hms]+\])[^\]]*\]/i, "").downcase
      if bare.include?("%") then :percent
      elsif bare.match?(/[dy]/) then :date
      elsif bare.include?("[") then :duration
      elsif bare.match?(/[hs]/) then :time
      elsif bare.include?("m") then :date
      end
    end

    # xl/workbook.xml: the sheets in order, and which calendar the dates count in
    class Book < Package::Handler
      Listed = Data.define(:name, :id)

      attr_reader :sheets, :date1904

      def initialize
        super
        @sheets = []
      end

      def start_element_namespace(name, attributes = [], *)
        case name
        when "workbookPr"
          @date1904 = attribute(attributes, "date1904").in?(%w[1 true])
        when "sheet"
          hidden = attribute(attributes, "state").in?(%w[hidden veryHidden])
          @sheets << Listed.new(name: attribute(attributes, "name").to_s.truncate(MAX_CELL_LENGTH), id: attribute(attributes, "id")) unless hidden || @sheets.size >= MAX_LISTED
        end
      end

      def end_element_namespace(name, *)
        done! if name == "sheets"
      end
    end

    # xl/_rels/workbook.xml.rels: which part of the zip a sheet is
    class Relations < Package::Handler
      attr_reader :parts

      def initialize
        super
        @parts = {}
      end

      def start_element_namespace(name, attributes = [], *)
        return unless name == "Relationship" && attribute(attributes, "Type").to_s.end_with?("/worksheet") && @parts.size < MAX_LISTED

        target = attribute(attributes, "Target").to_s
        @parts[attribute(attributes, "Id")] = target.start_with?("/") ? target.delete_prefix("/") : "xl/#{target}"
      end
    end

    # xl/styles.xml: what kind of number a cell of each style shows
    class Styles < Package::Handler
      def initialize
        super
        @kinds = BUILT_IN_FORMATS.dup
        @styles = []
      end

      def start_element_namespace(name, attributes = [], *)
        case name
        when "numFmt" then @kinds[attribute(attributes, "numFmtId").to_i] = Workbook.kind_of_format(attribute(attributes, "formatCode")) if @kinds.size < MAX_STYLES
        when "cellXfs" then @cells = true
        when "xf" then @styles << attribute(attributes, "numFmtId").to_i if @cells && @styles.size < MAX_STYLES
        end
      end

      def end_element_namespace(name, *)
        @cells = false if name == "cellXfs"
      end

      def formats
        @styles.map { |format| @kinds[format] }
      end
    end

    # A sheet: its rows of cells. A cell is its text, or the number of a shared text.
    class Cells < Package::Handler
      attr_reader :more

      def initialize(formats, date1904)
        super()
        @formats = formats
        @epoch = date1904 ? Date.new(1904, 1, 1) : Date.new(1899, 12, 30)
        @rows = []
        @more = false
      end

      # Without the empty rows a sheet ends in
      def rows
        @rows.pop while @rows.any? && @rows.last.compact.empty?
        @rows
      end

      def start_element_namespace(name, attributes = [], *)
        case name
        when "row" then start_row(attribute(attributes, "r").to_i)
        when "c" then start_cell(attributes) if @row
        when "v" then @reading = (@value = +"") if @shown
        when "t" then @reading = (@text ||= +"") if @shown && !@phonetic
        when "rPh" then @phonetic = true
        end
        @more = true if name.in?(%w[v t]) && @row && !@shown
      end

      def characters(string)
        @reading << string if @reading && @reading.size <= MAX_CELL_LENGTH
      end
      alias_method :cdata_block, :characters

      def end_element_namespace(name, *)
        case name
        when "v", "t" then @reading = nil
        when "rPh" then @phonetic = false
        when "c" then end_cell
        when "row" then @row = nil
        when "sheetData" then done!
        end
      end

      private

      # A row says which one it is, so the empty rows before it are there too
      def start_row(number)
        number = @rows.size + 1 if number <= @rows.size
        return (@more = true) && done! if number > MAX_ROWS

        @rows << [] while @rows.size < number
        @row = @rows.last
        @column = -1
      end

      def start_cell(attributes)
        @column = column(attribute(attributes, "r"))
        @shown = @column < MAX_COLUMNS
        @type = attribute(attributes, "t")
        @style = attribute(attributes, "s").to_i
        @value = @text = nil
      end

      def end_cell
        @row[@column] = content if @row && @shown
        @shown = false
      end

      # The column a cell says it is in (the letters of "BC12"), counted from 0, or the
      # next one. Two letters reach column 702: whatever has more lies past what is shown,
      # and isn't worked out (a cell can say it is in a column of a million letters).
      def column(reference)
        letters = reference.to_s[/\A[A-Z]+/]
        return @column + 1 unless letters
        return MAX_COLUMNS if letters.size > 2

        letters.each_char.reduce(0) { |number, letter| number * 26 + letter.ord - 64 } - 1
      end

      def content
        case @type
        when "s" then Integer(@value.to_s, 10, exception: false)
        when "inlineStr" then @text
        when "b" then @value == "1" ? "TRUE" : "FALSE"
        when "str", "e", "d" then @value
        else @text || number(@value)
        end
      end

      def number(value)
        number = Float(value.to_s, exception: false)
        return value.presence unless number&.finite?

        case @formats[@style]
        when :percent then "#{plain(number * 100)}%"
        when :time then time(number % 1)
        when :duration then time(number)
        when :date then date(number)
        else plain(number)
        end
      end

      def plain(number)
        number == number.to_i ? number.to_i.to_s : number.round(10).to_s
      end

      # A date is the number of days since the workbook's first day, a time the part of a day
      def date(number)
        return plain(number) unless number.between?(0, 2_958_465)

        seconds = ((number % 1) * 86_400).round
        day = (@epoch + number.floor).iso8601
        seconds.zero? ? day : format("%s %02d:%02d", day, seconds / 3600, seconds / 60 % 60)
      end

      def time(number)
        return plain(number) unless number.between?(0, 2_958_465)

        seconds = (number * 86_400).round
        clock = format("%d:%02d", seconds / 3600, seconds / 60 % 60)
        (seconds % 60).zero? ? clock : format("%s:%02d", clock, seconds % 60)
      end
    end

    # xl/sharedStrings.xml: the texts the sheets name by number, of which only the ones
    # that are shown are kept
    class Strings < Package::Handler
      attr_reader :strings

      def initialize(wanted)
        super()
        @wanted = wanted
        @last = wanted.max
        @index = -1
        @strings = {}
      end

      def start_element_namespace(name, *)
        case name
        when "si" then @text = (+"" if @wanted.include?(@index += 1))
        when "t" then @reading = @text unless @phonetic
        when "rPh" then @phonetic = true
        end
      end

      def characters(string)
        @reading << string if @reading && @reading.size <= MAX_CELL_LENGTH
      end
      alias_method :cdata_block, :characters

      def end_element_namespace(name, *)
        case name
        when "t" then @reading = nil
        when "rPh" then @phonetic = false
        when "si"
          @strings[@index] = @text if @text
          done! if @index >= @last
        end
      end
    end
  end
end
