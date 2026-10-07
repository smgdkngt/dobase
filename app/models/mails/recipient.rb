# frozen_string_literal: true

module Mails
  # Someone a mail goes to: an address, and the name it was written with
  # ("Ann Lee <ann@example.com>"). What isn't an address is kept as it was typed, to say so.
  Recipient = Data.define(:address, :name) do
    # A piece between commas, semicolons or lines; a quoted name may have those in it
    PIECE = /(?:"(?:[^"\\]|\\.)*"|<[^>]*>|[^,;\n])+/

    # Everyone in a To, Cc or Bcc as the compose form, the API or a paste gives it
    def self.parse(text)
      text.to_s.scan(PIECE).map(&:strip).reject(&:blank?).map { |piece| from(piece) }
    end

    def self.from(piece)
      parsed = Mail::Address.new(piece)
      new(parsed.address.presence || piece, parsed.display_name.presence)
    rescue Mail::Field::ParseError
      new(piece, nil)
    end

    def valid?
      address.match?(URI::MailTo::EMAIL_REGEXP)
    end

    # As a mail's header has it; the name is quoted where it has to be
    def to_s
      return address unless name.present? && valid?

      Mail::Address.new(address).tap { |with_name| with_name.display_name = name }.to_s
    end
  end
end
