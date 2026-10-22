# frozen_string_literal: true

module Mcp
  # Plain text as the HTML a rich text field takes, the way the dobase CLI
  # writes it (`command.Paragraphs`): a blank line starts a paragraph, a line
  # break stays one, and addresses become links.
  module Text
    URL = %r{\bhttps?://[^\s<>"]+}i
    TRAILING = %w[. , ; : ! ? ' "].freeze

    def self.paragraphs(text)
      text.to_s.chomp.split("\n", -1).map(&:rstrip)
        .chunk_while { |line, following| line.present? && following.present? }
        .reject { |lines| lines.all?(&:blank?) }
        .map { |lines| "<p>#{lines.map { link(it) }.join("<br>")}</p>" }
        .join
    end

    def self.link(line)
      html = +""
      rest = 0
      line.to_enum(:scan, URL).map { Regexp.last_match }.each do |match|
        url = trim(match[0])
        next if url.end_with?("://")

        html << ERB::Util.html_escape(line[rest...match.begin(0)])
        html << %(<a href="#{ERB::Util.html_escape(url)}">#{ERB::Util.html_escape(url)}</a>)
        rest = match.begin(0) + url.length
      end
      html << ERB::Util.html_escape(line[rest..])
    end

    # Punctuation that ends a sentence isn't part of an address, nor is a ")"
    # that closes a bracket opened before it
    def self.trim(url)
      loop do
        if TRAILING.include?(url[-1])
          url = url[...-1]
        elsif url.end_with?(")") && url.count(")") > url.count("(")
          url = url[...-1]
        else
          return url
        end
      end
    end
  end
end
