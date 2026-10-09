# frozen_string_literal: true

require "test_helper"

class FilePreviewTest < ActiveSupport::TestCase
  include OfficeFilesHelper

  def preview(name, content, content_type: "application/octet-stream")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: name, content_type: content_type, identify: false)
    FilePreview.new(blob)
  end

  def fixture(name, content_type: "application/octet-stream")
    preview(name, file_fixture(name).binread, content_type: content_type)
  end

  test "says what kind of file it is" do
    assert_equal "image", preview("photo.png", "x", content_type: "image/png").kind
    assert_equal "pdf", preview("letter.pdf", "x", content_type: "application/pdf").kind
    assert_equal "audio", preview("voice.mp3", "x", content_type: "audio/mpeg").kind
    assert_equal "video", preview("clip.mp4", "x", content_type: "video/mp4").kind
    assert_equal "text", preview("notes.txt", "Hello", content_type: "text/plain").kind
    assert_equal "table", preview("list.csv", "a,b\n1,2\n", content_type: "text/csv").kind
    assert_nil preview("archive.zip", "x", content_type: "application/zip").kind
  end

  test "an SVG is never a picture to show" do
    svg = preview("logo.svg", "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>", content_type: "image/svg+xml")

    assert_not svg.image?
    assert_nil svg.kind
  end

  test "an HTML file is text, shown as its source" do
    page = preview("page.html", "<script>alert(1)</script>", content_type: "text/html")

    assert_equal "text", page.kind
    assert_equal "<script>alert(1)</script>", page.preview_text
  end

  test "a csv is a table" do
    sheets = preview("list.csv", "Name,Amount\nAnn,\"1,5\"\nJoe,2\n", content_type: "text/csv").sheets

    assert_equal 1, sheets.size
    assert_equal [ %w[Name Amount], [ "Ann", "1,5" ], %w[Joe 2] ], sheets.first.rows
    assert_not sheets.first.more
  end

  test "a csv with semicolons, as a Dutch Excel writes it, is split on those" do
    sheets = preview("lijst.csv", "﻿Naam;Bedrag\nAnn;1,5\n").sheets

    assert_equal [ %w[Naam Bedrag], [ "Ann", "1,5" ] ], sheets.first.rows
  end

  test "a tsv is split on tabs" do
    assert_equal [ %w[a b], [ "1,5", "2" ] ], preview("list.tsv", "a\tb\n1,5\t2\n").sheets.first.rows
  end

  test "a csv that isn't UTF-8 is read as Windows wrote it" do
    assert_equal [ [ "café", "1" ] ], preview("list.csv", "caf\xE9,1\n".b).sheets.first.rows
  end

  test "a long or wide table is shown in part, and says so" do
    long = preview("long.csv", (1..FilePreview::MAX_ROWS + 5).map { |n| "#{n},x" }.join("\n")).sheets.first
    wide = preview("wide.csv", (1..FilePreview::MAX_COLUMNS + 5).to_a.join(",")).sheets.first

    assert_equal FilePreview::MAX_ROWS, long.rows.size
    assert long.more
    assert_equal FilePreview::MAX_COLUMNS, wide.rows.first.size
    assert wide.more
  end

  test "a spreadsheet is its sheets, with dates as dates and a formula's result" do
    sheets = fixture("sample.xlsx").sheets

    assert_equal %w[Budget Notes], sheets.map(&:name)
    assert_equal [
      %w[Date Item Amount],
      [ "2026-10-09", "Paper <b>", "12.5" ],
      [ "2026-10-10", "Ink", "30" ],
      [ "", "Total", "42.5" ]
    ], sheets.first.rows
    assert_equal [ [ "Second sheet" ] ], sheets.last.rows
  end

  test "a spreadsheet is known by its name or by its type" do
    type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    assert_equal "table", fixture("sample.xlsx").kind
    assert_equal "table", preview("budget", file_fixture("sample.xlsx").binread, content_type: type).kind
  end

  test "a file that is only called a spreadsheet has nothing to show" do
    assert_nil preview("fake.xlsx", "not a zip at all").sheets
    assert_nil preview("empty.xlsx", zipped("readme.txt" => "hello")).sheets
    assert_nil preview("fake.xlsx", "not a zip at all").kind
  end

  test "a workbook's cells are read by what kind they are" do
    sheet = preview("kinds.xlsx", xlsx("Kinds" => <<~XML, strings: [ "first", "second &amp; third" ], formats: [ "0.0%", "dd-mm-yyyy", "h:mm", "[h]:mm", "#,##0.00 &quot;d&quot;" ])).sheets.first
      <row r="1"><c r="A1" t="s"><v>1</v></c><c r="B1" t="inlineStr"><is><t>typed</t><rPh><t>spoken</t></rPh></is></c><c r="C1" t="b"><v>1</v></c><c r="D1" t="str"><v>a result</v></c></row>
      <row r="2"><c r="A2" s="1"><v>0.25</v></c><c r="B2" s="2"><v>46304</v></c><c r="C2" s="2"><v>46304.75</v></c><c r="D2" s="3"><v>46304.75</v></c></row>
      <row r="3"><c r="A3" s="4"><v>1.5</v></c><c r="B3" s="5"><v>12.5</v></c><c r="C3"><v>0.1</v></c><c r="D3"><f>A1+1</f></c></row>
    XML

    assert_equal [
      [ "second & third", "typed", "TRUE", "a result" ],
      [ "25%", "2026-10-09", "2026-10-09 18:00", "18:00" ],
      [ "36:00", "12.5", "0.1", "" ]
    ], sheet.rows
    assert_not sheet.more
  end

  test "a workbook's empty rows and cells stay where they are" do
    sheet = preview("gaps.xlsx", xlsx("Gaps" => <<~XML)).sheets.first
      <row r="1"><c r="A1"><v>1</v></c></row>
      <row r="4"><c r="C4"><v>2</v></c></row>
      <row r="5"><c r="A5" s="0"/></row>
    XML

    assert_equal [ [ "1", "", "" ], [ "", "", "" ], [ "", "", "" ], [ "", "", "2" ] ], sheet.rows
  end

  test "a sheet the workbook hides is not shown" do
    book = xlsx("Shown" => %(<row><c><v>1</v></c></row>), "Secret" => %(<row><c><v>2</v></c></row>), hidden: [ "Secret" ])

    assert_equal [ "Shown" ], preview("hidden.xlsx", book).sheets.map(&:name)
  end

  # The file the review of this reader was held up by: a cell that says it is in a column
  # hundreds of thousands to the right had its row filled up to there
  test "a cell that says it is far to the right fills nothing up" do
    sheet = preview("far.xlsx", xlsx("Far" => %(<row r="1"><c r="A1"><v>1</v></c><c r="ZZZZ1"><v>2</v></c><c r="ZZZZZZZZZZZZ1"><v>3</v></c></row>))).sheets.first

    assert_equal [ [ "1" ] ], sheet.rows
    assert sheet.more
  end

  test "a row that says it is far down fills nothing up" do
    sheet = preview("deep.xlsx", xlsx("Deep" => %(<row r="1"><c><v>1</v></c></row><row r="2000000"><c><v>2</v></c></row>))).sheets.first

    assert_equal [ [ "1" ] ], sheet.rows
    assert sheet.more
  end

  test "a workbook is read as far as a page shows it, however long it goes on" do
    rows = (1..FilePreview::MAX_ROWS + 5).map { |n| %(<row r="#{n}">#{(1..FilePreview::MAX_COLUMNS + 5).map { |c| "<c><v>#{c}</v></c>" }.join}</row>) }.join
    sheet = preview("long.xlsx", xlsx("Long" => rows + "<row><c><v>not XML any more")).sheets.first

    assert_equal [ FilePreview::MAX_ROWS, FilePreview::MAX_COLUMNS ], [ sheet.rows.size, sheet.rows.first.size ]
    assert sheet.more
  end

  # A zip of a few kilobytes can hold gigabytes. Each of these would be shown if nothing
  # counted what comes out: the rows are there, after the padding.
  test "a workbook with a part that unpacks to more than is read has nothing to show" do
    row = %(<row><c><v>1</v></c></row>)
    small = preview("small.xlsx", xlsx("Padded" => sheet_xml(row, before: padding(1.megabyte))))
    bomb = preview("bomb.xlsx", xlsx("Padded" => sheet_xml(row, before: padding(FilePreview::MAX_PART_BYTES))))

    assert_equal [ [ "1" ] ], small.sheets.first.rows
    assert_operator bomb.byte_size, :<, 100.kilobytes
    assert_nil bomb.sheets
    assert_nil bomb.kind
  end

  test "a workbook whose parts together unpack to more than is read has nothing to show" do
    part = sheet_xml(%(<row><c><v>1</v></c></row>), before: padding(FilePreview::MAX_PART_BYTES - 1.megabyte))
    parts = FilePreview::MAX_UNPACKED_BYTES / FilePreview::MAX_PART_BYTES + 1

    assert_equal 1, preview("one.xlsx", xlsx("A" => part)).sheets.size
    assert_nil preview("bomb.xlsx", xlsx(**(1..parts).to_h { |n| [ "Sheet #{n}", part ] })).sheets
  end

  test "a workbook's list of texts counts as a part too" do
    strings = %(<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">#{padding(FilePreview::MAX_PART_BYTES)}<si><t>text</t></si></sst>)

    assert_nil preview("strings.xlsx", xlsx("Texts" => %(<row><c t="s"><v>0</v></c></row>), extra: { "xl/sharedStrings.xml" => strings })).sheets
    assert_equal [ [ "text" ] ], preview("texts.xlsx", xlsx("Texts" => %(<row><c t="s"><v>0</v></c></row>), strings: [ "text" ])).sheets.first.rows
  end

  test "a zip that lists more files than are opened has nothing to show" do
    sheets = { "Sheet" => %(<row><c><v>1</v></c></row>) }
    files = ->(count) { (1..count).to_h { |n| [ "docProps/#{n}", "" ] } }

    assert_equal 1, preview("some.xlsx", xlsx(**sheets, extra: files.call(100))).sheets.size
    assert_nil preview("many.xlsx", xlsx(**sheets, extra: files.call(FilePreview::Package::MAX_ENTRIES))).sheets
  end

  test "reading stops when it takes too long or unpacks too much" do
    budget = FilePreview::Package::Budget
    workbook = file_fixture("sample.xlsx").to_s
    document = file_fixture("sample.docx").to_s

    assert_equal 2, FilePreview::Workbook.read(workbook, budget.new).size
    assert_nil FilePreview::Workbook.read(workbook, budget.new(seconds: -1))
    assert_nil FilePreview::Workbook.read(workbook, budget.new(bytes: 100))
    assert_equal 7, FilePreview::WordDocument.read(document, budget.new).blocks.size
    assert_nil FilePreview::WordDocument.read(document, budget.new(seconds: -1))
    assert_nil FilePreview::WordDocument.read(document, budget.new(bytes: 100))
  end

  test "a workbook or a document larger than is read has nothing to show" do
    workbook = fixture("sample.xlsx")
    document = fixture("sample.docx")
    [ workbook, document ].each { |file| file.blob.update_column(:byte_size, FilePreview::MAX_BYTES + 1) }

    assert_nil workbook.sheets
    assert_nil document.document
  end

  test "a csv of any size is read from its start" do
    line = "Ann,#{"x" * 98}\n"
    big = preview("big.csv", "Name,Note\n" + line * (FilePreview::MAX_SEPARATED_BYTES / line.bytesize + 10) + "\"never closed")
    sheet = big.sheets.first

    assert_operator big.byte_size, :>, FilePreview::MAX_SEPARATED_BYTES
    assert_equal FilePreview::MAX_ROWS, sheet.rows.size
    assert_equal %w[Name Note], sheet.rows.first
    assert sheet.more
  end

  test "of a csv no more is fetched than its start" do
    row = "#{"x" * (FilePreview::MAX_SEPARATED_BYTES * 0.45).to_i},1\n"
    sheet = preview("wide.csv", row * 3).sheets.first

    assert_equal 2, sheet.rows.size
    assert sheet.more
  end

  test "a csv cut off inside a character or a quoted field shows the rows before it" do
    line = "\"é, and\na second line\",1\n"
    sheet = preview("cut.csv", line * (FilePreview::MAX_SEPARATED_BYTES / line.bytesize + 10)).sheets.first

    assert_equal [ "é, and\na second line", "1" ], sheet.rows.last
    assert sheet.more
  end

  test "a csv in UTF-16, Excel's Unicode text, is read as that" do
    text = "Naam\tBedrag\nZoë\t1,5\n".encode(Encoding::UTF_16LE)

    assert_equal [ %w[Naam Bedrag], [ "Zoë", "1,5" ] ], preview("lijst.csv", "\xFF\xFE".b + text.b).sheets.first.rows
  end

  test "a separator inside quotes doesn't decide what a csv is split on" do
    assert_equal [ [ "Lee, Ann, Dr", "Amount" ], [ "x", "1" ] ], preview("names.csv", %("Lee, Ann, Dr";Amount\nx;1\n)).sheets.first.rows
  end

  test "a table's rows are all as wide as its widest" do
    assert_equal [ %w[a b c], [ "1", "", "" ] ], preview("ragged.csv", "a,b,c\n1\n").sheets.first.rows
  end

  test "a document is its headings, paragraphs, list items and tables, as text" do
    blocks = fixture("sample.docx").document.blocks

    assert_equal %i[heading paragraph heading list_item list_item table paragraph], blocks.map(&:kind)
    assert_equal [ "Quarterly report", 1 ], [ blocks[0].text, blocks[0].level ]
    assert_equal "Sales went up this quarter.", blocks[1].text
    assert_equal 2, blocks[2].level
    assert_equal "First point", blocks[3].text
    assert_equal [ %w[Region Total], %w[North 42] ], blocks[5].rows
    assert_equal "Closing <script> line.", blocks[6].text
  end

  test "a document's tabs and line breaks are kept, its empty paragraphs are not" do
    blocks = preview("note.docx", docx(<<~XML)).document.blocks
      <w:p><w:pPr><w:tabs><w:tab w:val="left"/></w:tabs></w:pPr><w:r><w:t>one</w:t><w:tab/><w:t>two</w:t><w:br/><w:t>three</w:t></w:r></w:p>
      <w:p></w:p>
      <w:p><w:pPr><w:pStyle w:val="Kop2"/></w:pPr><w:r><w:t>Dutch heading</w:t></w:r></w:p>
    XML

    assert_equal [ "one\ttwo\nthree", "Dutch heading" ], blocks.map(&:text)
    assert_equal [ :heading, 2 ], [ blocks.last.kind, blocks.last.level ]
  end

  test "a document's text is read wherever it stands, and once" do
    blocks = preview("boxes.docx", docx(<<~XML, before: %(<w:background w:color="FFFFFF"/>))).document.blocks
      <w:sdt><w:sdtContent>#{paragraph("In a content control")}</w:sdtContent></w:sdt>
      <w:p><w:r><mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
        <mc:Choice Requires="wps"><w:txbxContent>#{paragraph("In a text box")}</w:txbxContent></mc:Choice>
        <mc:Fallback><w:txbxContent>#{paragraph("In a text box")}</w:txbxContent></mc:Fallback>
      </mc:AlternateContent></w:r></w:p>
      <w:tbl><w:tr><w:tc>#{paragraph("Outer")}<w:tbl><w:tr><w:tc>#{paragraph("Inner")}</w:tc></w:tr></w:tbl></w:tc></w:tr></w:tbl>
      <a:p xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:t>Not Word's</a:t></a:p>
    XML

    assert_equal [ "In a content control", "In a text box", nil ], blocks.map(&:text)
    assert_equal [ [ "Outer\nInner" ] ], blocks.last.rows
  end

  test "a document is shown as far as a page holds, and says there is more" do
    long = preview("long.docx", docx(paragraph("w" * 300_000) * 2)).document
    many = preview("many.docx", docx(paragraph("x") * (FilePreview::WordDocument::MAX_BLOCKS + 5))).document
    wide = preview("wide.docx", docx("<w:tbl><w:tr>#{"<w:tc>#{paragraph("y" * 600)}</w:tc>" * (FilePreview::MAX_COLUMNS + 5)}</w:tr></w:tbl>")).document
    short = preview("short.docx", docx(paragraph("all of it"))).document

    assert_equal FilePreview::MAX_DOCUMENT_LENGTH, long.blocks.sum { |block| block.text.length }
    assert long.more
    assert_equal FilePreview::WordDocument::MAX_BLOCKS, many.blocks.size
    assert many.more
    assert_equal [ FilePreview::MAX_COLUMNS, FilePreview::MAX_CELL_LENGTH ], [ wide.blocks.first.rows.first.size, wide.blocks.first.rows.first.first.length ]
    assert wide.more
    assert_not short.more
  end

  test "a document reads nothing from outside itself" do
    xml = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE w:document [<!ENTITY secret SYSTEM "file:///etc/hostname">]>
      <w:document #{WORD}><w:body><w:p><w:r><w:t>before &secret; after</w:t></w:r></w:p></w:body></w:document>
    XML
    blocks = preview("xxe.docx", zipped("word/document.xml" => xml)).document.blocks

    assert_equal [ "before  after" ], blocks.map(&:text)
  end

  test "a document that says one thing a million times over says it not at all" do
    xml = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE w:document [<!ENTITY a "ha"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;"><!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>
      <w:document #{WORD}><w:body><w:p><w:r><w:t>laugh #{"&c;" * 10_000}</w:t></w:r></w:p></w:body></w:document>
    XML
    document = preview("laughs.docx", zipped("word/document.xml" => xml)).document

    assert_operator document&.blocks.to_a.sum { |block| block.text.length }, :<, 100
  end

  test "a file that is only called a document has nothing to show" do
    assert_nil preview("fake.docx", "not a zip at all").document
    assert_nil preview("other.docx", zipped("readme.txt" => "hello")).document
    assert_nil preview("broken.docx", zipped("word/document.xml" => "<w:document")).document
    assert_nil preview("empty.docx", zipped("word/document.xml" => "<w:document #{WORD}/>")).document
    assert_nil preview("fake.docx", "not a zip at all").kind
  end

  # Each of these would be shown if nothing counted what comes out: the text is there,
  # after the padding
  test "a document that unpacks to more than is read has nothing to show" do
    small = preview("small.docx", docx(paragraph("hello"), before: padding(1.megabyte)))
    bomb = preview("bomb.docx", docx(paragraph("hello"), before: padding(FilePreview::MAX_PART_BYTES)))

    assert_equal [ "hello" ], small.document.blocks.map(&:text)
    assert_operator bomb.byte_size, :<, 100.kilobytes
    assert_nil bomb.document
    assert_nil bomb.kind
  end

  # The other file the review was held up by: what a zip says a file unpacks to is the
  # zip's own word, and was believed
  test "a document that lies about how much it unpacks to has nothing to show" do
    honest = document_xml(paragraph("hello"), before: padding(1.megabyte))
    lying = document_xml(paragraph("hello"), before: padding(FilePreview::MAX_PART_BYTES))

    assert_equal [ "hello" ], preview("honest.docx", lying_zip("word/document.xml", honest, claims: honest.bytesize)).document.blocks.map(&:text)
    assert_nil preview("lying.docx", lying_zip("word/document.xml", lying, claims: 2.kilobytes)).document
  end

  test "a file in the Files tool is read the same way, by the name it has now" do
    item = tools(:my_files).file_items.create!(name: "budget.xlsx",
      file: { io: file_fixture("sample.xlsx").open, filename: "upload.bin", content_type: "application/octet-stream" })

    assert item.table?
    assert item.read?
    assert_equal %w[Budget Notes], item.sheets.map(&:name)
  end
end
