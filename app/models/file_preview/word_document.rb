# frozen_string_literal: true

class FilePreview
  # A .docx as its text in order: headings, paragraphs, list items and tables. No fonts,
  # colours, pictures, headers or footnotes. Only the document's own text part is read, as
  # it comes out of the zip (Package) and as far as a page shows it; nothing it links to
  # is fetched.
  module WordDocument
    # What was read, and whether the document had more than is shown
    Contents = Data.define(:blocks, :more)
    # kind: :heading (with a level), :paragraph, :list_item (text), or :table (rows of cell texts)
    Block = Data.define(:kind, :text, :level, :rows)

    MAX_BLOCKS = 3000
    BODY = "word/document.xml"

    def self.read(path, budget = Package::Budget.new)
      Package.open(path, budget) do |package|
        text = package.read(BODY, Text.new)
        Contents.new(blocks: text.blocks, more: text.more) if text&.body?
      end
    end

    class Text < Package::Handler
      # Word's own elements, and the same in the stricter flavour of the format
      WORD = %w[http://schemas.openxmlformats.org/wordprocessingml/2006/main http://purl.oclc.org/ooxml/wordprocessingml/main].freeze

      attr_reader :blocks, :more

      def initialize
        super
        @blocks = []
        @more = false
        @room = MAX_DOCUMENT_LENGTH
        @paragraphs = @tables = @fallbacks = 0
      end

      def body?
        @body
      end

      def start_element_namespace(name, attributes = [], _prefix = nil, uri = nil, _namespaces = [])
        # A text box is in the file twice, for programs that can and can't draw it
        return @fallbacks += 1 if name == "Fallback"
        return if done? || @fallbacks.positive? || !uri.in?(WORD)

        case name
        when "body" then @body = true
        when "tbl" then @rows = [] if (@tables += 1) == 1
        when "tr" then @row = [] if @tables == 1
        when "tc" then @cell = [] if @tables == 1
        when "p" then start_paragraph if (@paragraphs += 1) == 1
        when "pStyle" then @style ||= attribute(attributes, "val").to_s
        when "numPr" then @list = true
        when "tabs" then @tab_stops = true
        when "t" then @reading = true
        when "tab" then write("\t") unless @tab_stops
        when "br", "cr" then write("\n")
        end
      end

      def characters(string)
        write(string) if @reading && !done?
      end
      alias_method :cdata_block, :characters

      def end_element_namespace(name, _prefix = nil, uri = nil)
        return @fallbacks -= 1 if name == "Fallback"
        return if done? || @fallbacks.positive? || !uri.in?(WORD)

        case name
        when "t" then @reading = false
        when "tabs" then @tab_stops = false
        when "p" then end_paragraph if (@paragraphs -= 1).zero?
        when "tc" then end_cell if @tables == 1
        when "tr" then end_row if @tables == 1
        when "tbl" then end_table if (@tables -= 1).zero?
        when "body" then done!
        end
      end

      private

      # The text of a paragraph, as far as there is room for more of the document
      def write(string)
        return unless @text && @body

        if string.length > @room
          @text << string[0, @room]
          cut_short
        else
          @text << string
          @room -= string.length
        end
      end

      def start_paragraph
        @text = +""
        @style = nil
        @list = false
      end

      # A paragraph in a table is a line of its cell, in a table in a table too
      def end_paragraph
        text = @text.to_s.strip
        @text = nil
        if @cell then @cell << text
        elsif @tables.zero? && text.present? then add(paragraph(text))
        end
      end

      # A style goes by its name without what isn't ASCII: "Überschrift 1" is berschrift1
      def paragraph(text)
        if (level = @style.to_s[/\A(?:Heading|Kop|Titre|berschrift|Ttulo)\s?(\d)\z/i, 1])
          Block.new(kind: :heading, text: text, level: level.to_i.clamp(1, 6), rows: nil)
        elsif @style.to_s.match?(/\A(Title|Titel)\z/i)
          Block.new(kind: :heading, text: text, level: 1, rows: nil)
        elsif @list || @style.to_s.match?(/\AList/i)
          Block.new(kind: :list_item, text: text, level: nil, rows: nil)
        else
          Block.new(kind: :paragraph, text: text, level: nil, rows: nil)
        end
      end

      def end_cell
        @row.size < MAX_COLUMNS ? @row << @cell.join("\n").strip.truncate(MAX_CELL_LENGTH) : @more = true if @row
        @cell = nil
      end

      def end_row
        @rows.size < MAX_ROWS ? @rows << @row : @more = true if @rows && @row
        @row = nil
      end

      def end_table
        add(Block.new(kind: :table, text: nil, level: nil, rows: @rows)) if @rows&.any?
        @rows = nil
      end

      def add(block)
        @blocks.size < MAX_BLOCKS ? @blocks << block : cut_short
      end

      # Enough: what was being read is kept as far as it got, the rest of the file is left
      def cut_short
        return if done?

        @more = true
        done!
        end_paragraph if @text
        end_cell if @cell
        end_row if @row
        end_table if @rows
      end
    end
  end
end
