# frozen_string_literal: true

require "test_helper"

class Tools::FilePreviewsControllerTest < ActionDispatch::IntegrationTest
  include OfficeFilesHelper

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  def attach(record, name, content, content_type: "application/octet-stream")
    record.file.attach(io: StringIO.new(content), filename: name, content_type: content_type, identify: false)
    record.file.attachment
  end

  def mail_attachment(message, name, content, **options)
    attach message.attachments.create!(filename: name, content_type: options[:content_type], file_size: content.bytesize), name, content, **options
  end

  def chat_tool
    chat_type = ToolType.find_or_create_by!(slug: "chat") do |tool_type|
      tool_type.name = "Chat"
      tool_type.icon = "messages-square"
    end
    Tool.create!(name: "Team chat", owner: @user, tool_type: chat_type)
  end

  test "a spreadsheet attached to a mail is shown as a table" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "budget.xlsx", file_fixture("sample.xlsx").binread)

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select "turbo-frame#file_viewer" do
      assert_select "h2", "budget.xlsx"
      assert_select "a[href*='disposition=attachment']", text: /Download/
      assert_select ".sheet-preview-name", "Budget"
      assert_select "table.cell-table td", "2026-10-09"
      assert_select "table.cell-table td", "42.5"
    end
  end

  test "a draft's attachment is shown like any other" do
    attachment = mail_attachment(mails_messages(:draft_message), "notes.csv", "Name;Amount\nAnn;3\n", content_type: "text/csv")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select "table.cell-table tr", 2
    assert_select "table.cell-table td", "Ann"
  end

  test "what a file holds is text on the page, never markup" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "evil.csv", "<script>alert(1)</script>,<img src=x onerror=alert(1)>\n", content_type: "text/csv")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select "table.cell-table td", "<script>alert(1)</script>"
    assert_select "table.cell-table script", 0
    assert_select "table.cell-table img", 0
  end

  test "what a document, a sheet's name and a file's name hold is text too" do
    markup = "&lt;img src=x onerror=alert(1)&gt;"
    styled = ->(style) { %(<w:p><w:pPr><w:pStyle w:val="#{style}"/></w:pPr><w:r><w:t>#{markup} #{style}</w:t></w:r></w:p>) }
    text = docx(styled.call("Heading1") + styled.call("ListParagraph") + styled.call("Normal") + "<w:tbl><w:tr><w:tc>#{styled.call("Normal")}</w:tc></w:tr></w:tbl>")
    # A file's name is cleaned when it is stored; the name it is given in the Files tool is not
    document = tools(:my_files).file_items.create!(name: "<b>report</b>.docx", file: { io: StringIO.new(text), filename: "report.docx" }).file.attachment
    workbook = mail_attachment(mails_messages(:inbox_unread), "sums.xlsx", xlsx(markup => "<row><c><v>1</v></c></row>", "Second" => "<row><c><v>2</v></c></row>"))

    get tool_file_preview_path(tools(:my_files), document)

    assert_response :success
    assert_select "img, b", 0
    assert_select "#file-viewer-title", "<b>report</b>.docx"
    assert_select ".document-preview h1", "<img src=x onerror=alert(1)> Heading1"
    assert_select ".document-preview li", "<img src=x onerror=alert(1)> ListParagraph"
    assert_select ".document-preview > p", "<img src=x onerror=alert(1)> Normal"
    assert_select ".document-preview td", "<img src=x onerror=alert(1)> Normal"

    get tool_file_preview_path(tools(:my_mail), workbook)

    assert_response :success
    assert_select "img", 0
    assert_select ".sheet-preview-name", "<img src=x onerror=alert(1)>"
  end

  test "a markdown attachment loads no picture from outside" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "readme.md", "# Hello\n\n![a chart](https://tracker.example/open.png?who=sem)\n", content_type: "text/markdown")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select ".markdown-preview h1", "Hello"
    assert_select "img", 0
    assert_select ".markdown-preview a[target=_blank]", "a chart"
    assert_equal "https://tracker.example/open.png?who=sem", css_select(".markdown-preview p a").first["href"]
    assert_not_includes response.body, "src=\"https://tracker.example"
  end

  test "a long document is shown in part, and says so" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "long.docx", docx(paragraph("w" * 300_000) * 2))

    get tool_file_preview_path(tools(:my_mail), attachment), headers: viewer

    assert_response :success
    assert_select ".file-preview-note", /Only the first part of this document/
    assert_operator response.body.bytesize, :<, FilePreview::MAX_DOCUMENT_LENGTH + 100.kilobytes

    get tool_file_preview_path(tools(:my_mail), attachment), headers: api_headers(@user, permission: "read")

    assert response.parsed_body["more"]
    assert_equal FilePreview::MAX_DOCUMENT_LENGTH, response.parsed_body["blocks"].sum { |block| block["text"].length }
  end

  test "a file that unpacks to more than is read is offered as a download" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "bomb.xlsx",
      xlsx("Padded" => sheet_xml("<row><c><v>1</v></c></row>", before: padding(FilePreview::MAX_PART_BYTES))))

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select "table.cell-table", 0
    assert_select ".file-viewer-body a", text: /Download/
  end

  test "an HTML attachment is shown as its source, not as a page" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "page.html", "<h1 id='theirs'>Hi</h1><script>alert(1)</script>", content_type: "text/html")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select "#theirs", 0
    assert_select ".file-viewer-body script", 0
    assert_includes css_select(".file-viewer-body pre").text, "<h1 id='theirs'>Hi</h1>"
  end

  test "an SVG is offered as a download, not drawn" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "logo.svg", "<svg xmlns='http://www.w3.org/2000/svg'/>", content_type: "image/svg+xml")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select ".file-viewer-body img", 0
    assert_select ".file-viewer-body iframe", 0
    assert_select ".file-viewer-body a", text: /Download/
  end

  test "a document on a card is shown as its text" do
    attachment = attach(boards_cards_attachment(cards(:first_task), "report.docx"), "report.docx", file_fixture("sample.docx").binread)

    get tool_file_preview_path(tools(:project_board), attachment)

    assert_response :success
    assert_select ".document-preview h1", "Quarterly report"
    assert_select ".document-preview li", "First point"
    assert_select ".document-preview table.cell-table td", "North"
  end

  test "a pdf on a todo is shown by the browser" do
    item = todo_items(:pending_one)
    attachment = attach(item.attachments.create!(filename: "letter.pdf", content_type: "application/pdf", file_size: 4), "letter.pdf", "%PDF", content_type: "application/pdf")

    get tool_file_preview_path(item.list.tool, attachment)

    assert_response :success
    assert_select ".file-viewer-body iframe[src*='/rails/active_storage/']"
  end

  test "a picture in a chat is shown as a picture" do
    tool = chat_tool
    message = tool.chat.messages.create!(user: @user, body: "<p>Look</p>",
      files: [ { io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png" } ])

    get tool_file_preview_path(tool, message.files.first)

    assert_response :success
    assert_select ".file-viewer-body img[alt='sample.png']"
  end

  test "a file in the Files tool goes by the name it has there" do
    item = tools(:my_files).file_items.create!(name: "renamed.csv", file: { io: StringIO.new("a,b\n"), filename: "upload.bin", content_type: "application/octet-stream" })

    get tool_file_preview_path(tools(:my_files), item.file.attachment)

    assert_response :success
    assert_select "h2", "renamed.csv"
    assert_select "table.cell-table td", "a"
  end

  test "a file that can't be shown says so and offers the download" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "slides.pptx", "PK", content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation")

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :success
    assert_select ".file-viewer-body a", text: /Download/
  end

  test "asked for by the viewer, only the frame comes back" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello", content_type: "text/plain")

    get tool_file_preview_path(tools(:my_mail), attachment), headers: viewer

    assert_response :success
    assert_select "turbo-frame#file_viewer pre", "Hello"
    assert_select "nav", 0
  end

  test "a file of another tool is not found, also for someone who has both tools" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello", content_type: "text/plain")

    get tool_file_preview_path(tools(:project_board), attachment), headers: viewer

    assert_response :not_found
    assert_select "turbo-frame#file_viewer", /no longer exists/
  end

  test "a file in a tool you don't have is not shown" do
    attachment = mail_attachment(mails_messages(:other_inbox), "secret.txt", "Secret", content_type: "text/plain")

    get tool_file_preview_path(tools(:other_mail), attachment)

    assert_redirected_to root_path
    assert_not_includes response.body, "Secret"
  end

  test "another tool's id doesn't get you a file you may not see" do
    attachment = mail_attachment(mails_messages(:other_inbox), "secret.txt", "Secret", content_type: "text/plain")

    get tool_file_preview_path(tools(:my_mail), attachment), headers: viewer

    assert_response :not_found
    assert_select "turbo-frame#file_viewer", /no longer exists/
  end

  test "what isn't a tool's file is never shown: someone's avatar" do
    @user.avatar.attach(io: file_fixture("sample.png").open, filename: "me.png", content_type: "image/png")

    get tool_file_preview_path(tools(:my_mail), @user.avatar.attachment), headers: viewer

    assert_response :not_found
    assert_select "turbo-frame#file_viewer", /no longer exists/
  end

  test "nobody signed in sees nothing" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello", content_type: "text/plain")
    reset!

    get tool_file_preview_path(tools(:my_mail), attachment)

    assert_response :redirect
    assert_not_includes response.body.to_s, "Hello"
  end

  test "the API gives what was read out of the file" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "budget.xlsx", file_fixture("sample.xlsx").binread)

    get tool_file_preview_path(tools(:my_mail), attachment), headers: api_headers(@user, permission: "read")

    assert_response :success
    body = response.parsed_body
    assert_equal "budget.xlsx", body["name"]
    assert_equal "table", body["kind"]
    assert_equal %w[Budget Notes], body["sheets"].map { |sheet| sheet["name"] }
    assert_equal [ "", "Total", "42.5" ], body["sheets"].first["rows"].last
    assert_match %r{/rails/active_storage/}, body["download_url"]
  end

  test "the API gives a document's blocks and a text file's text" do
    document = mail_attachment(mails_messages(:inbox_unread), "report.docx", file_fixture("sample.docx").binread)
    text = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello", content_type: "text/plain")
    headers = api_headers(@user, permission: "read")

    get tool_file_preview_path(tools(:my_mail), document), headers: headers
    assert_equal({ "kind" => "heading", "text" => "Quarterly report", "level" => 1 }, response.parsed_body["blocks"].first)

    get tool_file_preview_path(tools(:my_mail), text), headers: headers
    assert_equal "Hello", response.parsed_body["text"]
  end

  test "a token for someone without the tool gets nothing" do
    attachment = mail_attachment(mails_messages(:inbox_unread), "notes.txt", "Hello", content_type: "text/plain")

    get tool_file_preview_path(tools(:my_mail), attachment), headers: api_headers(users(:two))

    assert_response :forbidden
  end

  private

  # As the viewer over the page asks
  def viewer = { "Turbo-Frame" => "file_viewer" }

  def boards_cards_attachment(card, name)
    card.attachments.create!(filename: name, content_type: "application/octet-stream", file_size: 1)
  end
end
