# frozen_string_literal: true

require "test_helper"

module Mails
  class TrailingQuoteTest < ActiveSupport::TestCase
    def folded(html)
      Loofah.html5_fragment(TrailingQuote.fold_html(html))
    end

    # What a reader sees without opening the fold
    def shown_text(html)
      fragment = folded(html)
      fragment.css("details.mail-quote").each(&:remove)
      fragment.text.squish
    end

    def quote_text(html)
      folded(html).at_css("details.mail-quote")&.text.to_s.squish
    end

    test "Gmail's quote, with the line that says who wrote it, is folded away" do
      html = %(<div dir="ltr">See you there.</div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Ann wrote:<br></div><blockquote class="gmail_quote">Shall we meet?</blockquote></div>)

      assert_equal "See you there.", shown_text(html)
      assert_match(/\AOn Mon, Ann wrote: ?Shall we meet\?\z/, quote_text(html))
    end

    test "Apple Mail's cited quote is folded away, and what wraps it stays in place" do
      html = %(<div>Booked.</div><div><br><blockquote type="cite"><div>On Nov 12, Ann wrote:</div><div>Can you book it?</div></blockquote></div>)

      assert_equal "Booked.", shown_text(html)
      assert_includes quote_text(html), "Can you book it?"
      # The fold sits where the quote was, inside the div around it, with the empty line above it
      fold = folded(html).at_css("details.mail-quote")
      assert_equal "div", fold.parent.name
      assert_equal %w[details], fold.parent.children.map(&:name)
    end

    test "Outlook's header and the mail under it are folded from the line above them" do
      html = %(<div>Fine by me.</div><div id="appendonsend"></div><hr style="display:inline-block;width:98%"><div id="divRplyFwdMsg"><b>From:</b> Ann<br><b>Sent:</b> Monday</div><div>Is Thursday fine?</div>)

      assert_equal "Fine by me.", shown_text(html)
      assert_includes quote_text(html), "From: Ann"
      assert_includes quote_text(html), "Is Thursday fine?"
      assert folded(html).at_css("details.mail-quote hr")
    end

    test "a blockquote at the end is folded along with the line that introduces it" do
      html = %(<p>Thanks!</p><p>On Monday, Ann Lee wrote:</p><blockquote><p>Here is the plan.</p></blockquote><p><br></p>)

      assert_equal "Thanks!", shown_text(html)
      assert_includes quote_text(html), "On Monday, Ann Lee wrote:"
    end

    test "a blockquote with an answer under it is part of the mail and stays" do
      html = %(<p>On Monday, Ann Lee wrote:</p><blockquote><p>Thursday?</p></blockquote><p>Yes, Thursday works.</p>)

      assert_equal html, TrailingQuote.fold_html(html)
    end

    test "a mail that is nothing but a quote is left whole" do
      html = %(<div class="gmail_quote"><blockquote class="gmail_quote">Only this.</blockquote></div>)

      assert_equal html, TrailingQuote.fold_html(html)
    end

    test "a forwarded mail is what the mail is about and isn't folded" do
      html = %(<div>FYI</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Ann</div><div>The contract.</div></div>)

      assert_equal html, TrailingQuote.fold_html(html)
    end

    test "the fold is a button of three dots that needs no script" do
      fragment = folded(%(<p>Yes.</p><blockquote type="cite">Shall we?</blockquote>))

      summary = fragment.at_css("details.mail-quote > summary")
      assert summary
      assert_equal "Show the quoted text", summary["title"]
      assert summary.at_css("svg")
      assert_empty fragment.css("script, [onclick]")
    end

    test "mail without a quote is left as it was" do
      html = %(<p>Hello</p><p>Bye</p>)
      assert_equal html, TrailingQuote.fold_html(html)
      assert_equal "", TrailingQuote.fold_html("")
    end

    test "a text mail is split before the quoted lines at its end and the line that introduces them" do
      text = "Booked.\n\nAnn\n\nOn Monday, Ann Lee wrote:\n> Can you book it?\n>\n> > Shall we?\n\n"

      assert_equal [ "Booked.\n\nAnn", "On Monday, Ann Lee wrote:\n> Can you book it?\n>\n> > Shall we?" ], TrailingQuote.split_text(text)
    end

    test "a text mail with answers between the quoted lines, or nothing but them, isn't split" do
      interleaved = "> Thursday?\nYes.\n> Dinner too?\nYes."
      assert_equal [ interleaved, nil ], TrailingQuote.split_text(interleaved)

      only = "> Thursday?\n> Dinner too?"
      assert_equal [ only, nil ], TrailingQuote.split_text(only)

      assert_equal [ "Just text.", nil ], TrailingQuote.split_text("Just text.")
    end
  end
end
