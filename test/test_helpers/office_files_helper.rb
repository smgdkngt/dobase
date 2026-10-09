# frozen_string_literal: true

require "zip"

# Builds the files FilePreview reads, small and to order: a test says what is in a
# workbook or a document, and what the zip claims about itself.
module OfficeFilesHelper
  WORD = %(xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main")

  # A zip with these files in it, as an .xlsx and a .docx are
  def zipped(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  # A zip of one file that says it unpacks to `claims` bytes, whatever it holds
  def lying_zip(name, content, claims:)
    packed = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS).deflate(content, Zlib::FINISH)
    sizes = [ Zlib.crc32(content), packed.bytesize, claims, name.bytesize ]
    local = [ 0x04034b50, 20, 0, 8, 0, 0x5d49, *sizes, 0 ].pack("VvvvvvVVVvv") + name
    listed = [ 0x02014b50, 20, 20, 0, 8, 0, 0x5d49, *sizes, 0, 0, 0, 0, 0, 0 ].pack("VvvvvvvVVVvvvvvVV") + name
    local + packed + listed + [ 0x06054b50, 0, 0, 1, 1, listed.bytesize, local.bytesize + packed.bytesize, 0 ].pack("VvvvvVVv")
  end


  def document_xml(body, before: "")
    %(<?xml version="1.0" encoding="UTF-8"?>\n<w:document #{WORD}>#{before}<w:body>#{body}</w:body></w:document>)
  end

  def docx(body, **options)
    zipped("word/document.xml" => document_xml(body, **options))
  end

  def paragraph(text)
    "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>"
  end

  def sheet_xml(rows, before: "")
    %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">#{before}<sheetData>#{rows}</sheetData></worksheet>)
  end

  # A workbook of these sheets, each given as the XML of its rows (or of the whole sheet)
  def xlsx(strings: [], formats: [], hidden: [], extra: {}, **sheets)
    listed = sheets.keys.each_with_index.map { |name, n| %(<sheet name="#{name}" sheetId="#{n + 1}" r:id="rId#{n + 1}"#{' state="hidden"' if name.in?(hidden)}/>) }
    relations = sheets.keys.each_index.map do |n|
      %(<Relationship Id="rId#{n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{n + 1}.xml"/>)
    end
    main = %(xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main")

    zipped({
      "xl/workbook.xml" => %(<workbook #{main} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{listed.join}</sheets></workbook>),
      "xl/_rels/workbook.xml.rels" => %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{relations.join}</Relationships>),
      "xl/styles.xml" => %(<styleSheet #{main}><numFmts>#{formats.each_with_index.map { |code, n| %(<numFmt numFmtId="#{164 + n}" formatCode="#{code}"/>) }.join}</numFmts>
        <cellXfs><xf numFmtId="0"/>#{formats.each_index.map { |n| %(<xf numFmtId="#{164 + n}"/>) }.join}</cellXfs></styleSheet>),
      "xl/sharedStrings.xml" => %(<sst #{main}>#{strings.map { |string| "<si><t>#{string}</t></si>" }.join}</sst>)
    }.merge(sheets.values.each_with_index.to_h { |rows, n| [ "xl/worksheets/sheet#{n + 1}.xml", rows.start_with?("<worksheet") ? rows : sheet_xml(rows) ] }).merge(extra))
  end

  # Whitespace a reader has to unpack and can make nothing of
  def padding(bytes)
    " " * bytes
  end
end
