# frozen_string_literal: true

module Mails
  # The text part of an HTML mail, the way mail programs write one: a blank line
  # between paragraphs, "- " and "1. " before list items and "> " before quoted lines.
  class PlainText
    BLOCKS = %w[
      p div h1 h2 h3 h4 h5 h6 section article header footer main aside nav address center
      figure figcaption details summary dl dt dd table thead tbody tfoot tr td th caption form fieldset
    ].freeze

    def self.from_html(html)
      new(html).to_s
    end

    def initialize(html)
      @fragment = Loofah.html5_fragment(html.to_s)
      @fragment.css("style, script, title, head").each(&:remove)
    end

    def to_s
      blocks(@fragment.children).join("\n\n")
    end

    private

    # The children as paragraphs of text; inline content between blocks makes one of its own
    def blocks(nodes)
      paragraphs = []
      inline = +""

      nodes.each do |node|
        if node.element? && block?(node)
          paragraphs << squish(inline)
          inline = +""
          paragraphs.concat(block(node))
        else
          inline << inline_text(node)
        end
      end

      (paragraphs << squish(inline)).reject(&:empty?)
    end

    def block?(node)
      BLOCKS.include?(node.name) || %w[blockquote ul ol pre hr].include?(node.name)
    end

    def block(node)
      case node.name
      when "blockquote"
        quoted = blocks(node.children).join("\n\n")
        [ quoted.lines(chomp: true).map { |line| line.empty? ? ">" : "> #{line}" }.join("\n") ]
      when "ul", "ol"
        [ list(node) ]
      when "pre"
        [ node.text.rstrip ]
      when "hr"
        [ "---" ]
      else
        blocks(node.children)
      end
    end

    def list(node)
      items = node.element_children.select { |child| child.name == "li" }
      items.each_with_index.map do |item, index|
        marker = node.name == "ol" ? "#{index + 1}. " : "- "
        text = blocks(item.children).join("\n")
        marker + text.lines(chomp: true).join("\n#{" " * marker.length}")
      end.join("\n")
    end

    def inline_text(node)
      if node.text?
        node.text.gsub(/\s+/, " ")
      elsif node.element? && node.name == "br"
        "\n"
      elsif node.element?
        node.children.map { |child| node_text(child) }.join
      else
        ""
      end
    end

    # A block inside inline content, like a <div> in a <span>, still starts a line
    def node_text(node)
      node.element? && block?(node) ? "\n#{blocks(node.children).join("\n")}\n" : inline_text(node)
    end

    def squish(text)
      text.gsub(/ *\n */, "\n").gsub(/\A\s+|\s+\z/, "").squeeze(" ")
    end
  end
end
