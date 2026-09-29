# frozen_string_literal: true

require "test_helper"

module Mails
  class OutgoingHtmlTest < ActiveSupport::TestCase
    test "paragraphs, lists and quotes carry their spacing inline, quoted lines sitting close" do
      html = OutgoingHtml.from("<p>Hi</p><ol><li><p>One</p></li></ol><blockquote><p>Lunch?</p><p><br></p><p>Ann</p></blockquote>")

      assert_equal '<p style="margin:0 0 1em 0">Hi</p>' \
        '<ol style="margin:0 0 1em 0;padding-left:1.5em"><li><p style="margin:0">One</p></li></ol>' \
        '<blockquote style="margin:0 0 1em 0;padding-left:1em;border-left:3px solid #d2d2d7;color:#6e6e73" type="cite">' \
        '<p style="margin:0">Lunch?</p><p style="margin:0"><br></p><p style="margin:0">Ann</p></blockquote>', html
    end

    test "elements with their own style keep it, and styling twice changes nothing" do
      html = OutgoingHtml.from('<p style="margin:0">Tight</p><blockquote type="cite">Quote</blockquote>')

      assert_includes html, '<p style="margin:0">Tight</p>'
      assert_equal html, OutgoingHtml.from(html)
    end

    test "text outside ASCII stays as it is" do
      assert_equal '<p style="margin:0 0 1em 0">Eén vraag – RMA’s</p>', OutgoingHtml.from("<p>Eén vraag – RMA’s</p>")
    end
  end
end
