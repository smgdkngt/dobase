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

    test "event handlers go, however they're written" do
      html = readable(<<~HTML)
        <body onload="alert(1)">
        <p onclick="alert(1)">double</p><p onclick='alert(1)'>single</p><p onclick=alert(1)>bare</p>
        <p ONMOUSEOVER = "alert(1)">spaced</p><p
        onfocus="alert(1)" tabindex=0>on a new line</p>
        <img/onerror=alert(1)/src="cid:x"><img src="cid:x" onerror="alert(1)" onload=alert(1)>
        <p title=">" onclick="alert(1)">after a bracket</p><p title="x"onclick="alert(1)">glued</p>
        <a href="https://example.com" onclick="alert(1)" onauxclick="alert(1)">link</a>
        <svg onload="alert(1)"><animate onbegin="alert(1)" /></svg><details ontoggle="alert(1)" open>open</details>
        </body>
      HTML

      attributes = Nokogiri::HTML5.fragment(html).css("*").flat_map { |element| element.attribute_nodes.map(&:name) }
      assert_empty attributes.grep(/\Aon/i)
      assert_not_includes html, "alert"
      assert_includes html, %(<a href="https://example.com">link</a>)
    end

    test "text that reads like an event handler stays" do
      html = readable("<p>Totaal onkosten = 45,00 euro</p><p>Write &lt;p onclick=\"go()\"&gt; for that</p>")

      assert_includes html, "<p>Totaal onkosten = 45,00 euro</p>"
      assert_equal [ "Totaal onkosten = 45,00 euro", %(Write <p onclick="go()"> for that) ], Nokogiri::HTML5.fragment(html).css("p").map(&:text)
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
