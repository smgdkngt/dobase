# frozen_string_literal: true

require "application_system_test_case"

class FilePreviewTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tool = tools(:my_files)
    sign_in_as(@user)
  end

  def upload(name, content, content_type: "text/plain")
    @tool.file_items.create!(name: name, file: { io: StringIO.new(content), filename: name, content_type: content_type })
  end

  test "a text file shows its contents" do
    file = upload("notes.txt", "Remember the milk\nand the bread")

    visit tool_files_item_path(@tool, file)

    assert_selector "pre", text: "Remember the milk"
    assert_selector "pre", text: "and the bread"
  end

  test "a markdown file is rendered, and markup inside it is not" do
    file = upload("README.md", <<~MARKDOWN, content_type: "text/markdown")
      # Getting started

      - First step
      - Second step

      <img src=x onerror="window.__xss = true">
    MARKDOWN

    visit tool_files_item_path(@tool, file)

    assert_selector "h1", text: "Getting started"
    assert_selector "li", text: "First step"
    assert_no_selector "img[src='x']"
    assert_nil page.evaluate_script("window.__xss")
  end
  test "a markdown table and task list come out as a table and checkboxes" do
    file = upload("notes.md", <<~MARKDOWN, content_type: "text/markdown")
      | Tool | What it does |
      | --- | --- |
      | Boards | Cards in columns |

      - [x] Ticked
      - [ ] Not ticked
    MARKDOWN

    visit tool_files_item_path(@tool, file)

    assert_selector "table th", text: "What it does"
    assert_selector "table td", text: "Cards in columns"
    assert_selector "input[type='checkbox'][checked]", visible: :all
  end

  test "a shared text file can be read on its share page" do
    file = upload("shared-notes.txt", "Shared with everyone")
    share = Files::Share.create!(shareable: file, created_by: @user)

    using_session("a stranger") do
      visit share_path(share.token)

      assert_selector "pre", text: "Shared with everyone"
    end
  end
end
