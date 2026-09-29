# frozen_string_literal: true

module Mails
  # The HTML of a mail as it leaves Dobase. Mail programs each have their own idea of
  # how far apart paragraphs are and what a quote looks like, and many ignore <style>,
  # so the spacing the compose editor shows goes along as inline styles.
  class OutgoingHtml
    STYLES = {
      "p" => "margin:0 0 1em 0",
      "ul" => "margin:0 0 1em 0;padding-left:1.5em",
      "ol" => "margin:0 0 1em 0;padding-left:1.5em",
      "blockquote" => "margin:0 0 1em 0;padding-left:1em;border-left:3px solid #d2d2d7;color:#6e6e73"
    }.freeze

    def self.from(html)
      new(html).to_s
    end

    def initialize(html)
      @fragment = Loofah.html5_fragment(html.to_s)
    end

    # Elements that bring their own style, like those in a quoted mail, keep it
    def to_s
      @fragment.css(STYLES.keys.join(", ")).each do |element|
        element["style"] = element["style"].presence || style_for(element)
      end
      # Apple Mail and Thunderbird show a quote as a reply's quote by its type
      @fragment.css("blockquote").each { |quote| quote["type"] ||= "cite" }
      @fragment.to_html
    end

    private

    def style_for(element)
      # Quoted mail is written in lines, the way the compose editor shows it
      if element.name == "p" && (element.parent&.name == "li" || element.ancestors("blockquote").any?)
        "margin:0"
      else
        STYLES[element.name]
      end
    end
  end
end
