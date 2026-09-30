# frozen_string_literal: true

require "test_helper"

module Mails
  class ReadableHtmlTest < ActiveSupport::TestCase
    test "a signature keeps its background, so its white text shows" do
      html = readable(%(<table style="background: url('https://example.com/bg.png') no-repeat; background-size: 650px auto; border-radius: 20px"><tr><td><p style="color:white">Ann Example</p></td></tr></table>))

      assert_includes html, %(style="background: url('https://example.com/bg.png') no-repeat; background-size: 650px auto; border-radius: 20px")
      assert_includes html, %(<p style="color:white">Ann Example</p>)
    end

    test "old script hooks in CSS go" do
      html = readable(%(<p style="width: expression(alert(1)); behavior: url(x.htc)">Hi</p><style>p { -moz-binding: url(x.xml) }</style>))

      assert_not_includes html, "expression("
      assert_not_includes html, "behavior:"
      assert_not_includes html, "-moz-binding"
    end

    test "scripts and what isn't text go, with their text" do
      html = readable(%(<html><head><title>Notice</title></head><body><p onclick="alert(1)">Hi</p><script>alert(2)</script><iframe src="https://example.com"></iframe><a href="javascript:alert(3)">Go</a></body></html>))

      assert_equal "<p>Hi</p><a>Go</a>", html.strip
    end

    test "old table attributes stay" do
      html = readable(%(<table><tr><td background="https://example.com/bg.png" nowrap><font face="Arial" size="2">Hi</font></td></tr></table>))

      assert_includes html, %(background="https://example.com/bg.png")
      assert_includes html, %(<font face="Arial" size="2">Hi</font>)
    end

    private

    def readable(body_html)
      ReadableHtml.from(Message.new(body_html: body_html))
    end
  end
end
