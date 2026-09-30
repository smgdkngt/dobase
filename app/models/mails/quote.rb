# frozen_string_literal: true

module Mails
  # The mail a reply or forward carries below its own text, as it was written. It stays out
  # of the compose editor, which would flatten its layout into paragraphs, and is added when
  # the mail goes out, with the pictures it shows as inline parts of its own.
  class Quote
    # Pictures as inline parts of an outgoing mail, found by the cid: links in its HTML
    def self.add_inline_images(mail, images)
      Array(images).each do |image|
        mail.add_file(filename: image[:filename], content: image[:content], content_type: image[:content_type])
        part = mail.parts.last
        part.content_disposition = "inline; filename=#{image[:filename].to_s.inspect}"
        part.content_id = "<#{image[:content_id]}>"
      end
    end

    # The quote of a draft or reply, when it has one
    def self.of(message, forward: nil)
      quoted = message.quoted_message
      return unless quoted

      new(quoted, forward: forward.nil? ? quoted.message_id != message.in_reply_to : forward)
    end

    attr_reader :message

    def initialize(message, forward: false)
      @message = message
      @forward = forward
    end

    def forward?
      @forward
    end

    def to_html
      forward? ? "#{header_html}#{content_html}" : %(#{header_html}<blockquote type="cite">#{content_html}</blockquote>)
    end

    # "On Tue, Sep 29, 2026 at 10:23 AM, Ann <ann@example.com> wrote:", or the header block of a forward
    def header_lines
      from = "#{message.display_from} <#{message.from_address}>"
      if forward?
        [ "---------- Forwarded message ----------", "From: #{from}", "Date: #{sent_at}",
          "Subject: #{message.subject}", "To: #{message.to_addresses_list.join(', ')}" ]
      else
        [ "On #{sent_at}, #{from} wrote:" ]
      end
    end

    def header_html
      "<p>#{header_lines.map { |line| ERB::Util.html_escape(line) }.join('<br>')}</p>"
    end

    # The pictures the quote shows, as the mail's inline parts
    def inline_images
      images.map do |image|
        { filename: image.filename, content: image.file.download, content_type: image.content_type, content_id: content_id(image) }
      end
    end

    # Its own pictures are attachments of the quote, not of the mail it's in
    def image_ids
      images.map(&:id)
    end

    private

    def content_html
      if message.body_html.present?
        ReadableHtml.new(message.body_html_with_image_urls { |image| "cid:#{content_id(image)}" }).to_s
      else
        ERB::Util.html_escape(message.body_plain.to_s).split(/\n{2,}/).map { |paragraph| "<p>#{paragraph.gsub("\n", '<br>')}</p>" }.join
      end
    end

    def images
      message.inline_images.values.uniq
    end

    def content_id(image)
      "quote-#{image.id}@dobase"
    end

    def sent_at
      message.sent_at&.strftime("%a, %b %-d, %Y at %-I:%M %p")
    end
  end
end
