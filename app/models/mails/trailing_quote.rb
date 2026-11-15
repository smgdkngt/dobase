# frozen_string_literal: true

module Mails
  # The mail an answer carries along at its end: what was written before, quoted again by
  # every answer after it. A conversation shows each message, so the quote is folded away
  # behind a button of three dots, as compose does with its own (Gmail and Mail.app do
  # the same). In HTML the fold is a <details>, which opens without a script: the frame a
  # mail is shown in runs none. What is quoted between answers is part of the answer and
  # stays, and so is a forward, which is what the mail is about.
  class TrailingQuote
    # Where the mail programs start their quote: Outlook's header above the mail it
    # answers, Gmail's quote (with the line that says who wrote it), Thunderbird's line,
    # Yahoo's, and a blockquote (Mail.app's type="cite" among them)
    STARTS = "#divRplyFwdMsg, .gmail_quote, .moz-cite-prefix, .yahoo_quoted, blockquote"

    # A forward under a few words of its own is what the mail is about
    FORWARD = /\A\W*(forwarded message|begin forwarded message|doorgestuurd bericht|weitergeleitete nachricht|message transf[ée]r[ée])/i

    # Three dots, as Lucide draws them (more-horizontal), in the colour of the text around it
    DOTS = %(<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>)

    LABEL = "Show the quoted text"

    # The HTML with its quote at the end inside <details class="mail-quote">, or as it was
    def self.fold_html(html)
      new(html).folded || html.to_s
    end

    # The HTML without its quote at the end
    def self.strip_html(html)
      fragment = Loofah.html5_fragment(new(html).folded || html.to_s)
      fragment.css("details.mail-quote").each(&:remove)
      fragment.to_html
    end

    # A mail of text split into what was written and the "> " lines at its end, with the
    # line that introduces them ("On Monday, Ann wrote:"): [text, quote], or [text, nil]
    def self.split_text(text)
      lines = text.to_s.rstrip.lines(chomp: true)
      start = lines.length
      start -= 1 while start.positive? && (lines[start - 1].start_with?(">") || lines[start - 1].strip.empty?)
      start += 1 while start < lines.length && lines[start].strip.empty?
      return [ text, nil ] if start == lines.length

      if start.positive? && lines[start - 1].rstrip.end_with?(":")
        start -= 1
        # Gmail breaks a long one over two lines: "On Mon, … Ann Lee <ann@example.com>" and "wrote:"
        start -= 1 if start.positive? && lines[start].split.size < 4 && lines[start - 1].strip.present? && !lines[start - 1].start_with?(">")
      end

      before = lines[0...start].join("\n").rstrip
      return [ text, nil ] if before.strip.empty?

      [ before, lines[start..].join("\n") ]
    end

    def initialize(html)
      @html = html.to_s
    end

    def folded
      return if @html.blank?

      fragment = Loofah.html5_fragment(@html)
      start = fragment.css(STARTS).find { |candidate| trailing?(candidate) }
      return unless start

      first = start["id"] == "divRplyFwdMsg" ? outlook_line(start) : introduction(start)
      # The empty lines above it go along, or they stay as room above the button
      first = first.previous_sibling while first.previous_sibling && blank?(first.previous_sibling)
      details = fold(fragment, first)
      return if forward?(details) || nothing_but_the_quote?(fragment)

      fragment.to_html
    end

    private

    # Nothing written after it, at its own level (but for Outlook's header, which the mail
    # it answers follows) or around it
    def trailing?(node)
      return false if node.ancestors.any? { |ancestor| ancestor.name == "details" }

      following_blank = ->(element) { element.next_sibling.nil? || siblings_after(element).all? { |sibling| blank?(sibling) } }
      (node["id"] == "divRplyFwdMsg" || following_blank.(node)) &&
        node.ancestors.take_while { |ancestor| ancestor.is_a?(Nokogiri::XML::Element) }.all?(&following_blank)
    end

    # Outlook draws a line above its header
    def outlook_line(header)
      before = previous_shown(header)
      before = previous_shown(before) if before && before["id"] == "appendonsend"
      before&.name == "hr" ? before : header
    end

    # The line before a blockquote that says who wrote it, which ends in a colon
    def introduction(quote)
      return quote unless quote.name == "blockquote"

      line = previous_shown(quote)
      text = line&.text.to_s.squish
      line && text.end_with?(":") && text.length <= 300 && line.css("blockquote").empty? ? line : quote
    end

    def previous_shown(node)
      sibling = node.previous_sibling
      sibling = sibling.previous_sibling while sibling && blank?(sibling)
      sibling if sibling&.element?
    end

    def siblings_after(node)
      siblings = []
      sibling = node.next_sibling
      while sibling
        siblings << sibling
        sibling = sibling.next_sibling
      end
      siblings
    end

    def blank?(node)
      return true if node.comment?
      return node.text.strip.empty? if node.text?
      return false unless node.element?

      %w[img hr].exclude?(node.name) && node.css("img, hr").empty? && node.text.gsub(/[[:space:]]/, "").empty?
    end

    # The quote and whatever follows it at its level go into the fold, where it was
    def fold(fragment, first)
      details = Nokogiri::XML::Node.new("details", fragment.document)
      details["class"] = "mail-quote"
      summary = Nokogiri::XML::Node.new("summary", fragment.document)
      summary["title"] = LABEL
      summary["aria-label"] = LABEL
      summary.inner_html = DOTS
      details.add_child(summary)

      moved = [ first, *siblings_after(first) ]
      first.add_previous_sibling(details)
      moved.each { |node| details.add_child(node) }
      details
    end

    def forward?(details)
      details.text.squish.match?(FORWARD)
    end

    # A mail that is only a quote (a forward without a word of its own) shows it
    def nothing_but_the_quote?(fragment)
      rest = Loofah.html5_fragment(fragment.to_html)
      rest.css("details.mail-quote, style").each(&:remove)
      rest.text.gsub(/[[:space:]]/, "").empty? && rest.css("img").empty?
    end
  end
end
