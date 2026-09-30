# frozen_string_literal: true

module Mails
  # The HTML of a mail as the reading pane shows it, in a sandboxed frame that runs no
  # scripts, with its pictures in it (Message#body_html_with_inline_images); and as a quote
  # carries it along (Mails::Quote). Only elements and attributes that lay out text are kept.
  class ReadableHtml
    TAGS = %w[
      p br div span a strong b em i u s strike del ins q cite tt big nobr wbr
      ul ol li h1 h2 h3 h4 h5 h6 blockquote pre code
      table thead tbody tfoot tr th td caption col colgroup
      img hr center font
      header footer section article figure figcaption
      abbr address details summary mark small sub sup dl dt dd
      style
    ].freeze

    ATTRIBUTES = %w[
      href alt title src
      style class id dir lang
      width height align valign nowrap
      bgcolor background color border face size
      cellpadding cellspacing colspan rowspan start type
    ].freeze

    # Mail is laid out with each element's own CSS. Cleaning it the way web pages are would
    # drop background images, rounded corners and more, and leave a signature's white text
    # on white. The frame runs no scripts, and until the reader allows images its CSP keeps
    # the url()s from loading, so the CSS stays, without the old script hooks of IE and Firefox.
    class Scrubber < Rails::HTML::PermitScrubber
      SCRIPT_HOOKS = /expression\s*\(|javascript\s*:|-moz-binding|behavior\s*:/i

      def initialize
        super
        self.tags = TAGS
        self.attributes = ATTRIBUTES
      end

      private

      # A picture the mail carries along keeps its link to it
      def scrub_attribute(node, attr_node)
        return if attr_node.node_name == "src" && attr_node.value.match?(/\A\s*cid:/i)

        super
      end

      def scrub_css_attribute(node)
        style = node.attributes["style"]
        style.value = style.value.gsub(SCRIPT_HOOKS, "") if style
      end
    end

    def self.from(message)
      new(message.body_html_with_inline_images).to_s
    end

    def initialize(html)
      @html = html
    end

    def to_s
      fragment = Loofah.html5_fragment(@html.to_s)
      # Scrubbing drops elements it doesn't allow but keeps their text, which for these isn't
      # meant to be read (like the JSON-LD in GitHub's notifications)
      fragment.css("script, template, title").each(&:remove)
      fragment.css("style").each { |style| style.content = style.content.gsub(Scrubber::SCRIPT_HOOKS, "") }
      fragment.scrub!(Scrubber.new).to_html
    end
  end
end
