# frozen_string_literal: true

require "test_helper"

class FilesHelperTest < ActionView::TestCase
  include FilesHelper

  test "a code file is read by its name" do
    assert_equal Rouge::Lexers::Ruby, code_lexer("welcome_service.rb")
    assert_equal Rouge::Lexers::JSON, code_lexer("package.json")
  end

  test "a file with nothing to highlight gets no lexer" do
    assert_nil code_lexer("notes.txt")
    assert_nil code_lexer("server.log")
    assert_nil code_lexer("no-extension")
  end

  test "code comes back marked up and escaped" do
    html = highlighted_code("def hello = \"<script>\"", Rouge::Lexers::Ruby)

    assert_includes html, %(<span class="k">def</span>)
    assert_includes html, "&lt;script&gt;"
    assert_not_includes html, "<script>"
  end

  test "markdown renders without letting raw html through" do
    html = markdown_preview("# Title\n\n<script>alert(1)</script>\n\nA [link](https://example.com).")

    assert_includes html, "<h1>Title"
    assert_not_includes html, "<script>"
    assert_includes html, 'target="_blank"'
  end

  test "a markdown table keeps its table tags" do
    html = markdown_preview("| a | b |\n| --- | --- |\n| 1 | 2 |")

    assert_includes html, "<table>"
    assert_includes html, "<td>1</td>"
  end
end
