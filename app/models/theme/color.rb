# frozen_string_literal: true

class Theme
  # An sRGB colour, with the mixing and the WCAG contrast sums a theme needs.
  class Color
    HEX = /\A#\h{6}\z/

    attr_reader :red, :green, :blue, :opacity

    def self.hex?(value) = value.is_a?(String) && value.match?(HEX)

    def initialize(hex, opacity: 1.0)
      raise ArgumentError, "not a colour: #{hex.inspect}" unless self.class.hex?(hex)

      @red, @green, @blue = hex[1..].scan(/../).map(&:hex)
      @opacity = opacity
    end

    def self.rgb(red, green, blue)
      new(format("#%02x%02x%02x", *[ red, green, blue ].map { |channel| channel.round.clamp(0, 255) }))
    end

    WHITE = new("#ffffff")
    BLACK = new("#000000")

    # This colour with `amount` (0..1) of the other mixed in
    def mix(other, amount)
      self.class.rgb(*channels.zip(other.channels).map { |mine, theirs| mine + (theirs - mine) * amount })
    end

    def alpha(opacity) = self.class.new(hex, opacity: opacity)

    def luminance
      linear = channels.map do |channel|
        value = channel / 255.0
        value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    end

    def contrast(other)
      lighter, darker = [ luminance, other.luminance ].minmax.reverse
      (lighter + 0.05) / (darker + 0.05)
    end

    # As text on `background`: pushed towards white (on a dark page) or black until
    # it carries the ratio.
    def readable_on(background, ratio, dark:)
      toward(dark ? WHITE : BLACK) { |color| color.contrast(background) >= ratio }
    end

    # As a fill under `text`: pushed away from the text colour until that reads
    def readable_under(text, ratio)
      toward(text.luminance > 0.5 ? BLACK : WHITE) { |color| color.contrast(text) >= ratio }
    end

    def hex = format("#%02x%02x%02x", red, green, blue)

    def to_s
      opacity < 1 ? "rgba(#{red}, #{green}, #{blue}, #{opacity})" : hex
    end

    def ==(other) = other.is_a?(Color) && to_s == other.to_s

    protected

    def channels = [ red, green, blue ]

    private

    def toward(target)
      (0..20).each do |step|
        candidate = mix(target, step * 0.05)
        return candidate if yield(candidate)
      end
      target
    end
  end
end
