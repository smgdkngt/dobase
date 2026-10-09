# frozen_string_literal: true

class FilePreview
  # A .docx as its text in order: headings, paragraphs, list items and tables. No fonts,
  # colours, pictures, headers or footnotes. Only the document's own text part is read;
  # nothing it links to is fetched.
  module WordDocument
    # kind: :heading (with a level), :paragraph, :list_item (text), or :table (rows of cell texts)
    Block = Data.define(:kind, :text, :level, :rows)

    MAX_BLOCKS = 3000
    BODY = "word/document.xml"
    W = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

    def self.read(path)
      xml = Zip::File.open(path) do |zip|
        entry = zip.find_entry(BODY)
        next unless entry && FilePreview.unpacks_small?(zip) && entry.size <= FilePreview::MAX_BYTES

        entry.get_input_stream.read
      end
      return unless xml

      body = Nokogiri::XML(xml) { |config| config.nonet }.at_xpath("/w:document/w:body", W)
      return unless body

      body.xpath("w:p | w:tbl", W).first(MAX_BLOCKS).filter_map { |node| node.name == "tbl" ? table(node) : paragraph(node) }
    rescue Zip::Error, Nokogiri::XML::SyntaxError, IOError, SystemCallError
      nil
    end

    def self.paragraph(node)
      text = text_of(node)
      return if text.blank?

      # A style goes by its name without what isn't ASCII: "Überschrift 1" is berschrift1
      style = node.at_xpath("w:pPr/w:pStyle/@w:val", W).to_s
      if (level = style[/\A(?:Heading|Kop|Titre|berschrift|Ttulo)\s?(\d)\z/i, 1])
        Block.new(kind: :heading, text: text, level: level.to_i.clamp(1, 6), rows: nil)
      elsif style.match?(/\A(Title|Titel)\z/i)
        Block.new(kind: :heading, text: text, level: 1, rows: nil)
      elsif node.at_xpath("w:pPr/w:numPr", W) || style.match?(/\AList/i)
        Block.new(kind: :list_item, text: text, level: nil, rows: nil)
      else
        Block.new(kind: :paragraph, text: text, level: nil, rows: nil)
      end
    end

    def self.table(node)
      rows = node.xpath("w:tr", W).first(MAX_ROWS).map do |row|
        row.xpath("w:tc", W).first(MAX_COLUMNS).map { |cell| cell.xpath(".//w:p", W).map { |p| text_of(p) }.join("\n") }
      end
      Block.new(kind: :table, text: nil, level: nil, rows: rows) if rows.any?
    end

    # What a paragraph says: its runs of text, with tabs and line breaks as such
    def self.text_of(paragraph)
      paragraph.xpath(".//w:t | .//w:tab | .//w:br", W).map do |node|
        case node.name
        when "t" then node.text
        when "tab" then node.parent.name == "tabs" ? "" : "\t"
        else "\n"
        end
      end.join.strip
    end
  end
end
