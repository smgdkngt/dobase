# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # The sanitizer leaves < and > as they are inside an attribute, so text that
  # looks like a tag can sit in a title or an alt. These are what someone
  # writing rich text through the API could send.
  HOSTILE = [
    %q(<a href="https://example.com" title="<a onmouseover=alert(1) ">link</a>),
    %q(<img src="https://example.com/a.png" alt="<a onmouseover=alert(1) x=">),
    %q(<img alt="<a href='x'><script>alert(1)</script>" src="https://example.com/a.png">),
    %q(<a href="https://example.com" title="><img src=x onerror=alert(1)>">link</a>),
    %q(<p title="</a><img src=x onerror=alert(1)>">text</p>),
    %q(<p title='" onmouseover="alert(1)'>text</p>)
  ].freeze

  test "links open in a new tab" do
    html = externalize_links(%(<p>See <a href="https://example.com">this</a> and <a href="/here">that</a>.</p>).html_safe)

    links = Nokogiri::HTML5.fragment(html).css("a")
    assert_equal 2, links.size
    links.each do |link|
      assert_equal "_blank", link["target"]
      assert_equal "noopener", link["rel"]
    end
    assert_predicate html, :html_safe?
  end

  test "a link's own target and rel are replaced, not doubled" do
    html = externalize_links(%(<a href="https://example.com" target="_self" rel="opener">this</a>).html_safe)

    link = Nokogiri::HTML5.fragment(html).at_css("a")
    assert_equal %w[href rel target], link.attribute_nodes.map(&:name).sort
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
  end

  test "nothing comes back for nothing" do
    assert_nil externalize_links(nil)
    assert_equal "", externalize_links("")
  end

  test "text inside an attribute that looks like a tag stays text" do
    HOSTILE.each do |hostile|
      sanitized = sanitize(hostile)
      result = externalize_links(sanitized)

      assert_equal shape(sanitized, ignoring: %w[target rel]), shape(result, ignoring: %w[target rel]), "for #{hostile}"
      assert_equal text_attributes(sanitized), text_attributes(result), "for #{hostile}"
    end
  end

  test "rich text renders no element or attribute its author hid in an attribute" do
    HOSTILE.each do |hostile|
      rendered = ActionText::RichText.new(name: "body", body: hostile).to_s
      fragment = Nokogiri::HTML5.fragment(rendered)

      assert_empty fragment.css("script"), "for #{hostile}"
      fragment.css("*").each do |node|
        assert_empty node.attribute_nodes.map(&:name) - %w[class href src alt title target rel], "for #{hostile}"
      end
      # Each of them is one element, whatever its attributes say
      assert_equal 1, fragment.css("a, img, p, span").size, "for #{hostile}"
    end
  end

  private

  # Every element with the names of its attributes, in document order
  def shape(html, ignoring: [])
    Nokogiri::HTML5.fragment(html.to_s).css("*").map do |node|
      [ node.name, node.attribute_nodes.map(&:name).sort - ignoring ]
    end
  end

  def text_attributes(html)
    Nokogiri::HTML5.fragment(html.to_s).css("*").map { |node| [ node["title"], node["alt"] ] }
  end
end
