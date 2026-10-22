# frozen_string_literal: true

require "test_helper"

# The same HTML the dobase CLI writes for plain text (command.Paragraphs)
class Mcp::TextTest < ActiveSupport::TestCase
  test "blank lines make paragraphs and line breaks stay" do
    assert_equal "<p>One<br>two</p><p>Three</p>", Mcp::Text.paragraphs("One\ntwo\n\n\nThree\n")
  end

  test "text is escaped" do
    assert_equal "<p>a &lt;b&gt; &amp; c</p>", Mcp::Text.paragraphs("a <b> & c")
  end

  test "addresses become links, without the punctuation after them" do
    assert_equal %(<p>See <a href="https://example.com/a?b=1">https://example.com/a?b=1</a>.</p>),
      Mcp::Text.paragraphs("See https://example.com/a?b=1.")
    assert_equal %(<p>(see <a href="https://example.com">https://example.com</a>)</p>),
      Mcp::Text.paragraphs("(see https://example.com)")
    assert_equal %(<p><a href="https://en.wikipedia.org/wiki/Rails_(software)">https://en.wikipedia.org/wiki/Rails_(software)</a></p>),
      Mcp::Text.paragraphs("https://en.wikipedia.org/wiki/Rails_(software)")
  end

  test "nothing gives nothing" do
    assert_equal "", Mcp::Text.paragraphs("\n\n")
  end
end
