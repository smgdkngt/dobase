# frozen_string_literal: true

module BoardsHelper
  # A card's colours, as CSS values built on the label hues of tokens.css, so a theme
  # recolours them. They're kept here rather than in Tailwind classes, which its build
  # would purge for colours only named in the database.
  CARD_COLORS = %w[red orange yellow green blue purple].index_with do |name|
    hue = "var(--color-label-#{name})"
    {
      fill: hue,
      text: "color-mix(in srgb, #{hue} 55%, var(--color-text-primary))",
      bg_light: "color-mix(in srgb, #{hue} 14%, transparent)",
      ring: "color-mix(in srgb, #{hue} 40%, transparent)"
    }
  end.freeze

  def card_colors
    CARD_COLORS
  end

  def card_color(card)
    CARD_COLORS[card.color]
  end
end
