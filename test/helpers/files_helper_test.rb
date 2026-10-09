# frozen_string_literal: true

require "test_helper"

class FilesHelperTest < ActionView::TestCase
  include FilesHelper
  include ApplicationHelper

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

  test "a markdown link opens in a new tab" do
    link = Nokogiri::HTML5.fragment(markdown_preview("A [link](https://example.com).")).at_css("a")

    assert_equal "_blank", link["target"]
    assert_equal "noopener noreferrer", link["rel"]
  end

  # The sanitizer leaves < as it is inside an attribute, so a link's title can
  # hold text that looks like a link.
  test "a link title that looks like a tag stays a title" do
    [
      %([link](https://example.com "<a onmouseover=alert(1) ")),
      %(![<a onmouseover=alert(1) x=](https://example.com/a.png)),
      %([link](https://example.com '"><img src=x onerror=alert(1)>'))
    ].each do |markdown|
      fragment = Nokogiri::HTML5.fragment(markdown_preview(markdown))

      assert_equal 1, fragment.css("a, img").size, "for #{markdown}"
      fragment.css("*").each do |node|
        assert_empty node.attribute_nodes.map(&:name) - %w[href src alt title target rel], "for #{markdown}"
      end
    end
  end

  test "a markdown picture is a link to it, never loaded" do
    fragment = Nokogiri::HTML5.fragment(markdown_preview("Hi ![a chart](https://tracker.example/open.png?who=sem) and ![](https://tracker.example/b.png) ![local](pictures/c.png)"))

    assert_empty fragment.css("img")
    assert_not_includes fragment.to_html, "src="
    assert_equal [ [ "a chart", "https://tracker.example/open.png?who=sem" ], [ "https://tracker.example/b.png", "https://tracker.example/b.png" ] ],
      fragment.css("a").map { |link| [ link.text, link["href"] ] }
    assert_includes fragment.text, "local"
  end

  test "a markdown table keeps its table tags" do
    html = markdown_preview("| a | b |\n| --- | --- |\n| 1 | 2 |")

    assert_includes html, "<table>"
    assert_includes html, "<td>1</td>"
  end
end
