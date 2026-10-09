# frozen_string_literal: true

require "test_helper"
require "zip"

class FilePreviewTest < ActiveSupport::TestCase
  def preview(name, content, content_type: "application/octet-stream")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: name, content_type: content_type, identify: false)
    FilePreview.new(blob)
  end

  def fixture(name, content_type: "application/octet-stream")
    preview(name, file_fixture(name).binread, content_type: content_type)
  end

  # A zip with these files in it, as an .xlsx and a .docx are
  def zipped(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  def docx(body)
    zipped("word/document.xml" => <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>#{body}</w:body></w:document>
    XML
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

  test "a spreadsheet that unpacks to more than a page should read is left alone" do
    bomb = preview("bomb.xlsx", zipped("xl/worksheets/sheet1.xml" => "0" * (FilePreview::MAX_UNPACKED_BYTES + 1)))

    assert_operator bomb.byte_size, :<, 1.megabyte
    assert_nil bomb.sheets
  end

  test "a file larger than is read has nothing to show" do
    big = preview("big.csv", "a,b\n")
    big.blob.update_column(:byte_size, FilePreview::MAX_BYTES + 1)

    assert_nil big.sheets
  end

  test "a document is its headings, paragraphs, list items and tables, as text" do
    blocks = fixture("sample.docx").document_blocks

    assert_equal %i[heading paragraph heading list_item list_item table paragraph], blocks.map(&:kind)
    assert_equal [ "Quarterly report", 1 ], [ blocks[0].text, blocks[0].level ]
    assert_equal "Sales went up this quarter.", blocks[1].text
    assert_equal 2, blocks[2].level
    assert_equal "First point", blocks[3].text
    assert_equal [ %w[Region Total], %w[North 42] ], blocks[5].rows
    assert_equal "Closing <script> line.", blocks[6].text
  end

  test "a document's tabs and line breaks are kept, its empty paragraphs are not" do
    blocks = preview("note.docx", docx(<<~XML)).document_blocks
      <w:p><w:pPr><w:tabs><w:tab w:val="left"/></w:tabs></w:pPr><w:r><w:t>one</w:t><w:tab/><w:t>two</w:t><w:br/><w:t>three</w:t></w:r></w:p>
      <w:p></w:p>
      <w:p><w:pPr><w:pStyle w:val="Kop2"/></w:pPr><w:r><w:t>Dutch heading</w:t></w:r></w:p>
    XML

    assert_equal [ "one\ttwo\nthree", "Dutch heading" ], blocks.map(&:text)
    assert_equal [ :heading, 2 ], [ blocks.last.kind, blocks.last.level ]
  end

  test "a document reads nothing from outside itself" do
    xml = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE w:document [<!ENTITY secret SYSTEM "file:///etc/hostname">]>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>before &secret; after</w:t></w:r></w:p></w:body></w:document>
    XML
    blocks = preview("xxe.docx", zipped("word/document.xml" => xml)).document_blocks

    assert_equal [ "before  after" ], blocks.map(&:text)
  end

  test "a file that is only called a document has nothing to show" do
    assert_nil preview("fake.docx", "not a zip at all").document_blocks
    assert_nil preview("other.docx", zipped("readme.txt" => "hello")).document_blocks
    assert_nil preview("broken.docx", zipped("word/document.xml" => "<w:document")).document_blocks
  end

  test "a document that unpacks to more than a page should read is left alone" do
    bomb = preview("bomb.docx", zipped("word/document.xml" => "<w:document/>", "word/media/image1.png" => "0" * (FilePreview::MAX_UNPACKED_BYTES + 1)))

    assert_nil bomb.document_blocks
  end

  test "a file in the Files tool is read the same way, by the name it has now" do
    item = tools(:my_files).file_items.create!(name: "budget.xlsx",
      file: { io: file_fixture("sample.xlsx").open, filename: "upload.bin", content_type: "application/octet-stream" })

    assert item.table?
    assert item.read?
    assert_equal %w[Budget Notes], item.sheets.map(&:name)
  end
end
