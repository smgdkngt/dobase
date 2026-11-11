# frozen_string_literal: true

require "test_helper"

module Mails
  class PlainTextTest < ActiveSupport::TestCase
    test "paragraphs are split by a blank line and line breaks stay" do
      assert_equal "Hi Ann,\n\nThursday works.\nSee you then.",
        PlainText.from_html("<p>Hi Ann,</p>\n  <p>Thursday   works.<br>See you then.</p>")
    end

    test "list items get a dash or their number, nested lists are indented" do
      html = "<p>Agenda:</p><ol><li>Budget</li><li><p>Hiring</p><ul><li>Design</li><li>Support</li></ul></li></ol><p>Bye</p>"

      assert_equal "Agenda:\n\n1. Budget\n2. Hiring\n   - Design\n   - Support\n\nBye", PlainText.from_html(html)
    end

    test "quoted mail is prefixed with > on every line, deeper quotes with more" do
      html = "<p>Sounds good.</p><p>On Thu, Ann wrote:</p><blockquote><p>Lunch?</p><p>Or dinner<br>at 7</p>" \
        "<blockquote>First</blockquote></blockquote>"

      assert_equal "Sounds good.\n\nOn Thu, Ann wrote:\n\n> Lunch?\n>\n> Or dinner\n> at 7\n>\n> > First", PlainText.from_html(html)
    end

    test "styles, scripts and inline markup leave only the text" do
      html = "<html><head><title>T</title><style>p { color: red }</style></head><body>" \
        "<div>Fish &amp; <b>chips</b> <a href='https://example.com'>here</a></div><script>alert(1)</script></body></html>"

      assert_equal "Fish & chips here", PlainText.from_html(html)
    end

    test "mail that goes out says where a link on words of its own goes" do
      html = %(<p>The <a href="https://example.com/feed?token=AbC&amp;x=1">feed</a>, <a href="https://example.com/a">https://example.com/a</a>, ) +
        %(<a href="mailto:ann@example.com">ann@example.com</a> and <a href="https://www.example.com">www.example.com</a></p>)

      assert_equal "The feed <https://example.com/feed?token=AbC&x=1>, https://example.com/a, ann@example.com and www.example.com",
        PlainText.from_html(html, links: true)
      assert_equal "The feed, https://example.com/a, ann@example.com and www.example.com", PlainText.from_html(html)
    end

    test "blank html is empty text" do
      assert_equal "", PlainText.from_html(nil)
      assert_equal "", PlainText.from_html("<p> </p><p><br></p>")
    end
  end
end
